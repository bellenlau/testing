#!/usr/bin/env bash
set -euo pipefail

VERSION=${1:?QE version is required}
STACK_FILE=${2:?stack profile is required}
WORK_ROOT=${3:?work root is required}
FORCE_REBUILD=${4:-false}

source "${STACK_FILE}"
module purge
for module_name in "${MODULES[@]}"; do module load "${module_name}"; done
command -v cmake >/dev/null || { printf 'cmake is required\n' >&2; exit 1; }
command -v make >/dev/null || { printf 'make is required\n' >&2; exit 1; }

SOURCE_ROOT="${WORK_ROOT}/sources/q-e-${VERSION}"
BUILD_ROOT="${WORK_ROOT}/builds/${STACK_NAME}/qe-${VERSION}"
BUILD_DIR="${BUILD_ROOT}/cmake-build"
mkdir -p "${WORK_ROOT}/sources" "${WORK_ROOT}/builds/${STACK_NAME}"

if [[ ! -d "${SOURCE_ROOT}/.git" ]]; then
    git clone --branch "qe-${VERSION}" --depth 1 https://gitlab.com/QEF/q-e.git "${SOURCE_ROOT}" >&2
else
    git -C "${SOURCE_ROOT}" fetch --depth 1 origin "qe-${VERSION}" >&2
    git -C "${SOURCE_ROOT}" checkout --detach "qe-${VERSION}" >&2
fi

mkdir -p "${BUILD_ROOT}"
log_dir="${BUILD_ROOT}/logs"
mkdir -p "${log_dir}"

(
    cmake -S "${SOURCE_ROOT}" -B "${BUILD_DIR}" \
        -G "Unix Makefiles" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${BUILD_ROOT}" \
        "${CMAKE_ARGS[@]}" >"${log_dir}/configure.log" 2>&1
    if [[ "${FORCE_REBUILD}" == true ]]; then
        make -C "${BUILD_DIR}" clean >"${log_dir}/clean.log" 2>&1
    fi
    make -C "${BUILD_DIR}" -j "${BUILD_JOBS:-8}" >"${log_dir}/build.log" 2>&1
    make -C "${BUILD_DIR}" install >"${log_dir}/install.log" 2>&1
)

cat > "${BUILD_ROOT}/provenance.env" <<EOF
QE_VERSION=${VERSION}
STACK_NAME=${STACK_NAME}
STACK_FILE=${STACK_FILE}
SOURCE_ROOT=${SOURCE_ROOT}
CMAKE_ARGS=${CMAKE_ARGS[*]}
EOF

[[ -x "${BUILD_ROOT}/bin/pw.x" ]] || { printf 'build did not create pw.x\n' >&2; exit 1; }
printf '%s\n' "${BUILD_ROOT}"
