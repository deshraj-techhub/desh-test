#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

REPO_ROOT="$(resolve_repo_root)"
cd "${REPO_ROOT}"

RESULT_FILE=${1:-loadtest-report.md}

install_hey() {
  if command -v hey >/dev/null 2>&1; then
    return
  fi

  echo "Installing hey..."
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

  echo "Running load test for host ${host} (${requests} requests, concurrency ${concurrency})..."
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
  p90=$(awk '/90%/ {print $(NF-1)}' "${out_file}")
  p95=$(awk '/95%/ {print $(NF-1)}' "${out_file}")
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
  TARGET_URL="http://${HOST_IP}:${HOST_PORT}/"

  TMP_DIR=$(mktemp -d)
  trap 'rm -rf "${TMP_DIR}"' EXIT

  declare -A outputs
  declare -A total_requests
  declare -A total_conc

  if (( RANDOM % 2 )); then
    HOSTS=("foo.localhost" "bar.localhost")
  else
    HOSTS=("bar.localhost" "foo.localhost")
  fi

  echo "### Load test results" > "${RESULT_FILE}"
  echo "Target endpoint: ${TARGET_URL}" >> "${RESULT_FILE}"
  echo "" >> "${RESULT_FILE}"

  for host in "${HOSTS[@]}"; do
    local_requests=$((RANDOM % 151 + 200))
    local_concurrency=$((RANDOM % 16 + 5))
    out_file="${TMP_DIR}/${host//./_}.out"

    run_test "${host}" "${local_requests}" "${local_concurrency}" "${out_file}" "${TARGET_URL}"

    outputs["${host}"]="${out_file}"
    total_requests["${host}"]="${local_requests}"
    total_conc["${host}"]="${local_concurrency}"
  done

  for host in foo.localhost bar.localhost; do
    parse_results "${host}" "${total_requests[$host]}" "${total_conc[$host]}" "${outputs[$host]}"
  done

  echo "Load test report written to ${RESULT_FILE}"
}

main "$@"