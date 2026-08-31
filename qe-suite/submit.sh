#!/usr/bin/env bash
set -uo pipefail

RUN_ENV=${RUN_ENV:?RUN_ENV must point to the generated run environment}
source "${RUN_ENV}"
source "${STACK_FILE}"

module purge
for module_name in "${MODULES[@]}"; do module load "${module_name}"; done

export OMP_NUM_THREADS="${OMP_THREADS}"
export OMP_PLACES=cores
export OMP_PROC_BIND=close
export MKL_NUM_THREADS="${OMP_NUM_THREADS}"
export ESPRESSO_ROOT="${RUN_DIR}"
export ESPRESSO_BUILD="${QE_BUILD}"
export ESPRESSO_PSEUDO="${RUN_DIR}/pseudo"
export TESTCODE_DIR="${RUN_DIR}/test-suite/testcode"

cd "${RUN_DIR}/test-suite"
sed -i "s|\${shell pwd}/\.\.|${ESPRESSO_ROOT}|" ENVIRONMENT
sed -i "s|^export ESPRESSO_BUILD=.*|export ESPRESSO_BUILD=${ESPRESSO_BUILD}|" ENVIRONMENT

codes=(pw cp ph pp hp tddfpt kcw all_currents epw zg xsd-pw)
failures=0
status_file="${RUN_DIR}/categories.status"
status_tmp="${status_file}.tmp"
: > "${status_tmp}"
mv "${status_tmp}" "${status_file}"
for code in "${codes[@]}"; do
	log="${RUN_DIR}/test_out_${code}.log"
	started_at=$(date +%s)
	if make "run-tests-${code}" NPROCS="${SLURM_TASKS_PER_NODE}" >"${log}" 2>&1; then
		result=PASS
	else
		result=FAIL
		failures=1
	fi
	duration_seconds=$(( $(date +%s) - started_at ))
	printf '%s %s %s\n' "${code}" "${result}" "${duration_seconds}" | tee -a "${status_file}"
done

exit "${failures}"
