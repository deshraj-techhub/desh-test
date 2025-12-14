#!/usr/bin/env bash

# Utility helpers shared across scripts.

# shellcheck disable=SC2120
resolve_repo_root() {
  local current
  current="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # The scripts directory always lives one level beneath the repo root.
  (cd "${current}/.." >/dev/null 2>&1 && pwd)
}

# Detect the host IP/port that exposes ingress traffic from the KinD cluster.
# Priority order:
# 1. Environment overrides KIND_INGRESS_HOST / KIND_INGRESS_PORT
# 2. WSL2: use the control-plane container IP + NodePort
# 3. Default: 127.0.0.1 with hostPort 80 (due to extraPortMappings)
detect_ingress_endpoint() {
  local cluster_name host port
  cluster_name="${KIND_CLUSTER_NAME:-ci-cluster}"
  host="${KIND_INGRESS_HOST:-}"
  port="${KIND_INGRESS_PORT:-}"

  if [[ -z "${host}" ]]; then
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi "microsoft" /proc/version 2>/dev/null; then
      if command -v docker >/dev/null 2>&1; then
        host="$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${cluster_name}-control-plane" 2>/dev/null || true)"
      fi
    fi
  fi

  if [[ -z "${host}" ]]; then
    host="127.0.0.1"
  fi

  if [[ "${host}" == "127.0.0.1" ]]; then
    port="${port:-80}"
  else
    if [[ -z "${port}" ]]; then
      port="$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 2>/dev/null || true)"
    fi
    port="${port:-80}"
  fi

  echo "${host} ${port}"
}
