#!/usr/bin/env bash

# Utility helpers shared across scripts.

###############################################################################
# Logging helpers
###############################################################################

# Print an informational message with a timestamp.
log() {
  local level="INFO"
  local msg="$*"
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "${level}" "${msg}"
}

# Print an error message with a timestamp and exit non‑zero.
fatal() {
  local msg="$*"
  printf '[%s] [ERROR] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "${msg}" >&2
  exit 1
}

# Resolve the absolute path to the repository root regardless of where
# scripts are executed from.  The scripts directory always lives one
# directory beneath the repo root.
# shellcheck disable=SC2120
resolve_repo_root() {
  local current
  current="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
  (cd "${current}/.." >/dev/null 2>&1 && pwd)
}

# Detect the host IP/port that exposes ingress traffic from the KinD cluster.
# Priority order:
#   1. Environment overrides KIND_INGRESS_HOST / KIND_INGRESS_PORT
#   2. WSL2: use the control‑plane container IP + NodePort
#   3. Default: 127.0.0.1 with hostPort 80 (due to extraPortMappings)
detect_ingress_endpoint() {
  local cluster_name="${KIND_CLUSTER_NAME:-ci-cluster}"
  local host="${KIND_INGRESS_HOST:-}"
  local port="${KIND_INGRESS_PORT:-}"

  # On WSL2 the Kubernetes API server is exposed inside a Docker
  # container.  Use Docker to look up the container IP when no override is set.
  if [[ -z "${host}" ]]; then
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi "microsoft" /proc/version 2>/dev/null; then
      if command -v docker >/dev/null 2>&1; then
        host="$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${cluster_name}-control-plane" 2>/dev/null || true)"
      fi
    fi
  fi

  # Fallback to localhost when nothing else was discovered.
  if [[ -z "${host}" ]]; then
    host="127.0.0.1"
  fi

  # Determine the port.  Use the host port for localhost; otherwise look up the nodePort.
  if [[ "${host}" == "127.0.0.1" ]]; then
    port="${port:-80}"
  else
    if [[ -z "${port}" ]]; then
      port="$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 2>/dev/null || true)"
    fi
    port="${port:-80}"
  fi

  printf '%s %s\n' "${host}" "${port}"
}

###############################################################################
# Dependency checks
###############################################################################

# Verify that required commands are available.  Accepts a list of commands.
require_commands() {
  local missing=0
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      fatal "Required command '$cmd' not found on PATH"
      missing=1
    fi
  done
  return $missing
}
