#!/usr/bin/env bash
set -euo pipefail

JOB_ID=
RUN_DIR=
TIMEOUT=43200
POLL_INTERVAL=30

usage() {
    cat <<'EOF'
Usage: collect-results.sh --job-id ID --run-dir DIR [options]

Wait for a Slurm job and create summary.json plus junit.xml in its run directory.
  --job-id ID            Slurm job ID to inspect
  --run-dir DIR          Prepared QE run directory
  --timeout SECONDS      Maximum time to wait (default: 43200)
  --poll-interval SEC    Delay between sacct queries (default: 30)
EOF
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --job-id) JOB_ID=${2:?}; shift 2 ;;
        --run-dir) RUN_DIR=${2:?}; shift 2 ;;
        --timeout) TIMEOUT=${2:?}; shift 2 ;;
        --poll-interval) POLL_INTERVAL=${2:?}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

[[ -n "${JOB_ID}" ]] || die 'job ID is required'
[[ -d "${RUN_DIR}" ]] || die "run directory not found: ${RUN_DIR}"
[[ "${TIMEOUT}" =~ ^[1-9][0-9]*$ ]] || die 'timeout must be a positive integer'
[[ "${POLL_INTERVAL}" =~ ^[1-9][0-9]*$ ]] || die 'poll interval must be a positive integer'
command -v sacct >/dev/null || die 'sacct is required'
command -v jq >/dev/null || die 'jq is required'

summary_file="${RUN_DIR}/summary.json"
junit_file="${RUN_DIR}/junit.xml"
status_file="${RUN_DIR}/categories.status"
started_at=$(date +%s)
slurm_state=UNKNOWN
exit_code=unknown

is_terminal_state() {
    case "$1" in
        COMPLETED|FAILED|CANCELLED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE|REVOKED|SPECIAL_EXIT)
            return 0 ;;
        *) return 1 ;;
    esac
}

while :; do
    accounting=$(sacct -X -j "${JOB_ID}" --format=State,ExitCode --noheader --parsable2 2>/dev/null || true)
    record=$(awk -F'|' 'NF >= 2 && $1 != "" { print; exit }' <<<"${accounting}")
    if [[ -n "${record}" ]]; then
        IFS='|' read -r slurm_state exit_code <<<"${record}"
        slurm_state=${slurm_state%% *}
        if is_terminal_state "${slurm_state}"; then
            break
        fi
    fi

    if (( $(date +%s) - started_at >= TIMEOUT )); then
        slurm_state=TIMEOUT_WAITING_FOR_ACCOUNTING
        exit_code=unknown
        break
    fi
    sleep "${POLL_INTERVAL}"
done

categories_json='[]'
category_failures=0
test_count=0
status_missing=false
if [[ -f "${status_file}" ]]; then
    categories_json=$(awk 'NF >= 2 { print $1 "\t" $2 "\t" $3 }' "${status_file}" | \
        jq -Rn '[inputs | split("\t") | {name: .[0], status: .[1], duration_seconds: (.[2] | tonumber?)}]')
    test_count=$(jq 'length' <<<"${categories_json}")
    category_failures=$(jq '[.[] | select(.status != "PASS")] | length' <<<"${categories_json}")
else
    status_missing=true
fi

passed=false
if [[ "${slurm_state}" == COMPLETED && "${exit_code}" == 0:0 && ${category_failures} -eq 0 && ${test_count} -gt 0 && "${status_missing}" == false ]]; then
    passed=true
fi

jq -n \
    --arg job_id "${JOB_ID}" \
    --arg state "${slurm_state}" \
    --arg exit_code "${exit_code}" \
    --arg run_dir "${RUN_DIR}" \
    --argjson passed "${passed}" \
    --argjson categories "${categories_json}" \
    '{job_id: $job_id, slurm_state: $state, exit_code: $exit_code, run_dir: $run_dir, passed: $passed, categories: $categories}' \
    > "${summary_file}"

slurm_failure=0
if [[ "${slurm_state}" != COMPLETED || "${exit_code}" != 0:0 || "${status_missing}" == true ]]; then
    slurm_failure=1
fi
junit_tests=$(( test_count + slurm_failure ))
junit_failures=$(( category_failures + slurm_failure ))
{
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '<testsuite name="qe-regression" tests="%s" failures="%s">\n' "${junit_tests}" "${junit_failures}"
    while IFS=$'\t' read -r name status; do
        [[ -n "${name}" ]] || continue
        printf '  <testcase name="%s">' "${name}"
        if [[ "${status}" != PASS ]]; then
            printf '<failure message="category status: %s" />' "${status}"
        fi
        printf '</testcase>\n'
    done < <(jq -r '.[] | [.name, .status] | @tsv' <<<"${categories_json}")
    if [[ ${slurm_failure} -eq 1 ]]; then
        if [[ "${status_missing}" == true ]]; then
            printf '%s\n' '  <testcase name="status-record"><failure message="categories.status is missing" /></testcase>'
        else
            printf '  <testcase name="slurm-job"><failure message="Slurm state: %s, exit code: %s" /></testcase>\n' "${slurm_state}" "${exit_code}"
        fi
    fi
    printf '%s\n' '</testsuite>'
} > "${junit_file}"

printf 'Result summary: %s\n' "${summary_file}"
printf 'JUnit report: %s\n' "${junit_file}"
[[ "${passed}" == true ]]