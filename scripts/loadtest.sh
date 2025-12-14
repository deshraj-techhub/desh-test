#!/usr/bin/env bash
set -euo pipefail

# Run a simple load test against the http‑echo services using the hey tool.
# Request and concurrency ranges can be configured via environment variables:
#
#   REQUESTS_MIN  (default: 200)
#   REQUESTS_MAX  (default: 350)
#   CONCURRENCY_MIN (default: 5)
#   CONCURRENCY_MAX (default: 20)
#
# The script writes a Markdown report to the file passed as the first
# positional argument or to `loadtest-report.md` if unspecified.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# Verify required commands
require_commands kubectl curl awk sed

# Determine where to write the report
RESULT_FILE=${1:-loadtest-report.md}

# Default randomisation bounds.  Override via env vars to customise.
REQUESTS_MIN=${REQUESTS_MIN:-200}
REQUESTS_MAX=${REQUESTS_MAX:-350}
CONCURRENCY_MIN=${CONCURRENCY_MIN:-5}
CONCURRENCY_MAX=${CONCURRENCY_MAX:-20}

install_hey() {
  if command -v hey >/dev/null 2>&1; then
    return
  fi
  log "Installing hey load generator"
  curl -sL https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64 -o hey
  chmod +x hey
  if command -v sudo >/dev/null 2>&1; then
    sudo mv hey /usr/local/bin/hey
  elif [[ -w /usr/local/bin ]]; then
    mv hey /usr/local/bin/hey
  else
    mkdir -p "${HOME}/.local/bin"
    mv hey "${HOME}/.local/bin/hey"
    export PATH="${HOME}/.local/bin:${PATH}"
  fi
}

run_test() {
  local host=$1
  local requests=$2
  local concurrency=$3
  local out_file=$4
  local target_url=$5

  log "Running load test for host ${host} (${requests} requests, concurrency ${concurrency})"
  hey -n "${requests}" -c "${concurrency}" -H "Host: ${host}" "${target_url}" > "${out_file}"
}

parse_results() {
  local host=$1
  local requests=$2
  local concurrency=$3
  local out_file=$4

  local rps avg p90 p95 errors

  rps=$(awk '/Requests\/sec/ {print $2}' "${out_file}")
  avg=$(awk '/Average/ {print $2}' "${out_file}")
  # hey prints percentile lines in the form: "  90% in 0.0012 secs"
  p90=$(awk '/  *90%/ {print $(NF-1)}' "${out_file}")
  p95=$(awk '/  *95%/ {print $(NF-1)}' "${out_file}")
  errors=$(grep -m1 "Non-2xx" "${out_file}" 2>/dev/null | awk '{print $3}' || true)
  errors=${errors:-0}

  {
    echo "#### ${host}"
    echo "- Requests issued: ${requests}"
    echo "- Concurrency: ${concurrency}"
    echo "- Requests/sec: ${rps}"
    echo "- Avg latency (s): ${avg}"
    echo "- P90 latency (s): ${p90}"
    echo "- P95 latency (s): ${p95}"
    echo "- Non-2xx responses: ${errors}"
    echo
  } >> "${RESULT_FILE}"
}

main() {
  install_hey

  read -r HOST_IP HOST_PORT < <(detect_ingress_endpoint)
  local target_url="http://${HOST_IP}:${HOST_PORT}/"

  # Use a temporary directory for output files
  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap 'rm -rf "${tmp_dir:-}"' EXIT

  declare -A outputs
  declare -A total_requests
  declare -A total_conc

  # Randomise the order so the two hosts share concurrency differently per run
  local hosts=(foo.localhost bar.localhost)
  if (( RANDOM % 2 )); then
    hosts=(bar.localhost foo.localhost)
  fi

  echo "### Load test results" > "${RESULT_FILE}"
  echo "Target endpoint: ${target_url}" >> "${RESULT_FILE}"
  echo "" >> "${RESULT_FILE}"

  for host in "${hosts[@]}"; do
    local_requests=$((RANDOM % ((REQUESTS_MAX - REQUESTS_MIN + 1)) + REQUESTS_MIN))
    local_concurrency=$((RANDOM % ((CONCURRENCY_MAX - CONCURRENCY_MIN + 1)) + CONCURRENCY_MIN))
    local out_file="${tmp_dir}/${host//./_}.out"

    run_test "${host}" "${local_requests}" "${local_concurrency}" "${out_file}" "${target_url}"

    outputs["${host}"]="${out_file}"
    total_requests["${host}"]="${local_requests}"
    total_conc["${host}"]="${local_concurrency}"
  done

  # Present results in a predictable order
  for host in foo.localhost bar.localhost; do
    parse_results "${host}" "${total_requests[$host]}" "${total_conc[$host]}" "${outputs[$host]}"
  done

  log "Load test report written to ${RESULT_FILE}"
}

main "$@"