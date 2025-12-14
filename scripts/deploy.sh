#!/usr/bin/env bash
set -euo pipefail

# Top‑level deployment script.  Applies all manifests in the k8s/ directory,
# waits for resources to become ready and performs a simple ingress smoke test.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# Sanity check for required tools
require_commands kubectl curl

REPO_ROOT="$(resolve_repo_root)"
NAMESPACE="http-echo"

apply_manifests() {
  log "Applying Kubernetes manifests"
  # Apply the namespace first to ensure it exists
  kubectl apply -f "${REPO_ROOT}/k8s/namespace.yaml"
  # Then apply the rest (apply is idempotent)
  kubectl apply -f "${REPO_ROOT}/k8s/"
}

wait_for_deployments() {
  local deployments=(echo-foo echo-bar)
  for dep in "${deployments[@]}"; do
    log "Waiting for deployment/${dep} to become ready"
    kubectl rollout status "deployment/${dep}" -n "${NAMESPACE}" --timeout=180s
  done
}

smoke_test() {
  # Wait briefly for the ingress controller to pick up configuration changes
  sleep 10
  read -r HOST_IP HOST_PORT < <(detect_ingress_endpoint)

  log "Validating ingress routing via ${HOST_IP}:${HOST_PORT}"
  local foo_resp bar_resp
  foo_resp=$(curl -sS --retry 5 --retry-delay 3 --max-time 5 -H "Host: foo.localhost" "http://${HOST_IP}:${HOST_PORT}/") || true
  bar_resp=$(curl -sS --retry 5 --retry-delay 3 --max-time 5 -H "Host: bar.localhost" "http://${HOST_IP}:${HOST_PORT}/") || true

  log "foo.localhost response: ${foo_resp}"
  log "bar.localhost response: ${bar_resp}"

  if [[ "${foo_resp}" != "foo" ]]; then
    fatal "Unexpected response from foo.localhost (got '${foo_resp}')"
  fi
  if [[ "${bar_resp}" != "bar" ]]; then
    fatal "Unexpected response from bar.localhost (got '${bar_resp}')"
  fi
  log "Ingress and deployments are healthy"
}

main() {
  apply_manifests
  wait_for_deployments
  smoke_test
}

main "$@"