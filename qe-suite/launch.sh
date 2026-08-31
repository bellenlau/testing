#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKSPACE_ROOT=${WORKSPACE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}
WORK_ROOT="${WORKSPACE_ROOT}/work"
STACK_FILE=
VERSION=
SUBMIT=false
WAIT=false
FORCE_REBUILD=false
RUN_ID=
WAIT_TIMEOUT=43200

usage() {
    cat <<'EOF'
Usage: launch.sh --version VERSION --stack-file PROFILE [options]

Build or reuse Quantum ESPRESSO and prepare its full regression suite.
  --version VERSION       QE release, for example 7.5 or 7.6
  --stack-file PROFILE    Trusted shell profile under stacks/
    --force-rebuild         Rebuild QE even when a local build is available
  --submit                Submit the prepared suite with sbatch
    --wait                  Submit and collect the Slurm job result
    --run-id ID             Use an explicit run identifier
    --wait-timeout SECONDS  Maximum wait time for Slurm accounting (default: 43200)
EOF
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION=${2:?}; shift 2 ;;
        --stack-file) STACK_FILE=${2:?}; shift 2 ;;
        --force-rebuild) FORCE_REBUILD=true; shift ;;
        --submit) SUBMIT=true; shift ;;
        --wait) WAIT=true; SUBMIT=true; shift ;;
        --run-id) RUN_ID=${2:?}; shift 2 ;;
        --wait-timeout) WAIT_TIMEOUT=${2:?}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

[[ -n "${VERSION}" && -n "${STACK_FILE}" ]] || { usage >&2; exit 2; }
[[ "${WORKSPACE_ROOT}" != "${HOME}" && "${WORKSPACE_ROOT}" != "${HOME}"/* ]] || die 'workspace root must not be below HOME'
[[ "${WORK_ROOT}" == "${WORKSPACE_ROOT}"/* ]] || die "work root must be below ${WORKSPACE_ROOT}"
[[ -f "${STACK_FILE}" ]] || die "stack profile not found: ${STACK_FILE}"
[[ -z "${RUN_ID}" || "${RUN_ID}" =~ ^[A-Za-z0-9._-]+$ ]] || die 'run ID may contain only letters, digits, dot, underscore, and dash'
[[ "${WAIT_TIMEOUT}" =~ ^[1-9][0-9]*$ ]] || die 'wait timeout must be a positive integer'
STACK_FILE=$(cd "$(dirname "${STACK_FILE}")" && pwd)/$(basename "${STACK_FILE}")
command -v git >/dev/null || die 'git is required'
command -v module >/dev/null || die 'environment modules are required'

# Profiles are repository-controlled shell data, not user-provided arbitrary input.
source "${STACK_FILE}"
: "${STACK_NAME:?profile must set STACK_NAME}"
: "${SLURM_PARTITION:?profile must set SLURM_PARTITION}"
: "${SLURM_NODES:?profile must set SLURM_NODES}"
: "${SLURM_TASKS_PER_NODE:?profile must set SLURM_TASKS_PER_NODE}"
: "${SLURM_CPUS_PER_TASK:?profile must set SLURM_CPUS_PER_TASK}"
: "${OMP_THREADS:?profile must set OMP_THREADS}"
: "${MODULES[*]:?profile must set MODULES array}"
: "${CMAKE_ARGS[*]:?profile must set CMAKE_ARGS array}"
TEST_LAUNCHER=${TEST_LAUNCHER:-dcgp}
[[ "${TEST_LAUNCHER}" == booster || "${TEST_LAUNCHER}" == dcgp ]] || die "unsupported TEST_LAUNCHER: ${TEST_LAUNCHER}"
module purge
for module_name in "${MODULES[@]}"; do module load "${module_name}"; done

SOURCE_ROOT="${WORK_ROOT}/sources/q-e-${VERSION}"
LOCAL_QE_BUILD="${WORK_ROOT}/builds/${STACK_NAME}/qe-${VERSION}"
QE_BUILD=
if [[ "${FORCE_REBUILD}" == false && -x "${LOCAL_QE_BUILD}/bin/pw.x" ]]; then
    QE_BUILD="${LOCAL_QE_BUILD}"
    printf 'Reusing local QE %s at %s\n' "${VERSION}" "${QE_BUILD}"
elif [[ "${FORCE_REBUILD}" == false ]] && command -v pw.x >/dev/null; then
    installed_version=$(pw.x --version 2>&1 || true)
    if grep -Eq "Program PWSCF.*v\.?${VERSION//./\\.}([^0-9]|$)" <<<"${installed_version}"; then
        QE_BUILD=$(cd "$(dirname "$(command -v pw.x)")/.." && pwd)
        printf 'Reusing installed QE %s at %s\n' "${VERSION}" "${QE_BUILD}"
    fi
fi

if [[ -z "${QE_BUILD}" ]]; then
    QE_BUILD=$(${SCRIPT_DIR}/lib/build.sh "${VERSION}" "${STACK_FILE}" "${WORK_ROOT}" "${FORCE_REBUILD}")
fi

[[ -x "${QE_BUILD}/bin/pw.x" ]] || die "pw.x is unavailable at ${QE_BUILD}/bin/pw.x"
[[ -d "${SOURCE_ROOT}/test-suite" ]] || die "QE source test-suite missing: ${SOURCE_ROOT}/test-suite"

run_id=${RUN_ID:-"${STACK_NAME}-qe${VERSION}-$(date -u +%Y%m%dT%H%M%SZ)"}
RUN_DIR="${WORK_ROOT}/runs/${run_id}"
[[ ! -e "${RUN_DIR}" ]] || die "run directory already exists: ${RUN_DIR}"
mkdir -p "${RUN_DIR}"
cp -a "${SOURCE_ROOT}/test-suite" "${RUN_DIR}/test-suite"
cp -a "${SOURCE_ROOT}/pseudo" "${RUN_DIR}/pseudo"

if [[ "${TEST_LAUNCHER}" == booster ]]; then
    find "${RUN_DIR}/test-suite" -maxdepth 1 -name 'run-*.sh' -exec \
        sed -i 's|mpirun -np|mpirun --map-by socket:PE=$SLURM_CPUS_PER_TASK --rank-by core -np|g' {} +
else
    find "${RUN_DIR}/test-suite" -maxdepth 1 -name 'run-*.sh' -exec \
        sed -i 's|mpirun -np|srun --cpus-per-task=$SLURM_CPUS_PER_TASK --cpu-bind=cores -n|g' {} +
fi

export ESPRESSO_ROOT="${RUN_DIR}"
export ESPRESSO_BUILD="${QE_BUILD}"
export ESPRESSO_PSEUDO="${RUN_DIR}/pseudo"
export TESTCODE_DIR="${RUN_DIR}/test-suite/testcode"
make -C "${RUN_DIR}/test-suite" pseudo

cat > "${RUN_DIR}/run.env" <<EOF
VERSION=${VERSION}
STACK_FILE=${STACK_FILE}
QE_BUILD=${QE_BUILD}
SOURCE_ROOT=${SOURCE_ROOT}
RUN_DIR=${RUN_DIR}
TEST_LAUNCHER=${TEST_LAUNCHER}
EOF

cp "${SCRIPT_DIR}/submit.sh" "${RUN_DIR}/submit.sh"
sed -i "s|^RUN_ENV=.*|RUN_ENV=${RUN_DIR}/run.env|" "${RUN_DIR}/submit.sh"
sed -i "2i#SBATCH --partition=${SLURM_PARTITION}\n#SBATCH --nodes=${SLURM_NODES}\n#SBATCH --ntasks-per-node=${SLURM_TASKS_PER_NODE}\n#SBATCH --cpus-per-task=${SLURM_CPUS_PER_TASK}" "${RUN_DIR}/submit.sh"
[[ -n "${SLURM_TIME:-}" ]] && sed -i "2i#SBATCH --time=${SLURM_TIME}" "${RUN_DIR}/submit.sh"
[[ -n "${SLURM_ACCOUNT:-}" ]] && sed -i "2i#SBATCH --account=${SLURM_ACCOUNT}" "${RUN_DIR}/submit.sh"
[[ -n "${SLURM_QOS:-}" ]] && sed -i "2i#SBATCH --qos=${SLURM_QOS}" "${RUN_DIR}/submit.sh"
[[ -n "${SLURM_GRES:-}" ]] && sed -i "2i#SBATCH --gres=${SLURM_GRES}" "${RUN_DIR}/submit.sh"
chmod +x "${RUN_DIR}/submit.sh"
printf 'Prepared suite: %s\n' "${RUN_DIR}"
printf 'RUN_DIR=%s\n' "${RUN_DIR}"

if [[ "${SUBMIT}" == false ]]; then
    exit 0
fi

command -v sbatch >/dev/null || die 'sbatch is required for --submit'
sbatch_args=(
    --parsable
    --output="${RUN_DIR}/slurm-%j.out"
    --partition="${SLURM_PARTITION}"
    --time="${SLURM_TIME:-24:00:00}"
    --nodes="${SLURM_NODES}"
    --ntasks-per-node="${SLURM_TASKS_PER_NODE}"
    --cpus-per-task="${SLURM_CPUS_PER_TASK}"
    --exclusive
)
[[ -n "${SLURM_ACCOUNT:-}" ]] && sbatch_args+=(--account="${SLURM_ACCOUNT}")
[[ -n "${SLURM_QOS:-}" ]] && sbatch_args+=(--qos="${SLURM_QOS}")
[[ -n "${SLURM_GRES:-}" ]] && sbatch_args+=(--gres="${SLURM_GRES}")
job_id=$(sbatch "${sbatch_args[@]}" "${RUN_DIR}/submit.sh")
printf 'Submitted job: %s\n' "${job_id}"
printf 'JOB_ID=%s\n' "${job_id}"
printf '%s\n' "${job_id}" > "${RUN_DIR}/job.id"

if [[ "${WAIT}" == true ]]; then
    bash "${SCRIPT_DIR}/lib/collect-results.sh" \
        --job-id "${job_id}" \
        --run-dir "${RUN_DIR}" \
        --timeout "${WAIT_TIMEOUT}"
fi
