#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "${SCRIPT_DIR}/../../work"
TEST_ROOT=$(mktemp -d "${SCRIPT_DIR}/../../work/collect-results-test.XXXXXX")
MOCK_BIN="${TEST_ROOT}/bin"
COLLECTOR="${SCRIPT_DIR}/../lib/collect-results.sh"

mkdir -p "${MOCK_BIN}"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "${MOCK_SACCT_OUTPUT}"' > "${MOCK_BIN}/sacct"
chmod +x "${MOCK_BIN}/sacct"

run_collector() {
    PATH="${MOCK_BIN}:${PATH}" bash "${COLLECTOR}" --job-id 123 --run-dir "$1" --timeout 1 --poll-interval 1
}

success_run="${TEST_ROOT}/success"
mkdir -p "${success_run}"
printf '%s\n' 'pw PASS 12' 'ph PASS 4' > "${success_run}/categories.status"
MOCK_SACCT_OUTPUT='COMPLETED|0:0' run_collector "${success_run}"
jq -e '.passed == true and .categories[0].duration_seconds == 12' "${success_run}/summary.json" >/dev/null
xmllint --noout "${success_run}/junit.xml"

failed_run="${TEST_ROOT}/failed"
mkdir -p "${failed_run}"
printf '%s\n' 'pw FAIL 3' > "${failed_run}/categories.status"
if MOCK_SACCT_OUTPUT='FAILED|1:0' run_collector "${failed_run}"; then
    printf '%s\n' 'collector accepted a failed Slurm job' >&2
    exit 1
fi
jq -e '.passed == false and .slurm_state == "FAILED"' "${failed_run}/summary.json" >/dev/null
xmllint --noout "${failed_run}/junit.xml"

printf '%s\n' 'collect-results tests passed'