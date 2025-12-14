#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

REPO_ROOT="$(resolve_repo_root)"
cd "${REPO_ROOT}"

NAMESPACE=http-echo

echo "Creating namespace..."
kubectl apply -f k8s/namespace.yaml

echo "Deploying http-echo services..."
kubectl apply -f k8s/deploy-foo.yaml
kubectl apply -f k8s/deploy-bar.yaml
kubectl apply -f k8s/ingress.yaml

echo "Waiting for deployments to be ready..."
kubectl rollout status deployment/echo-foo -n "${NAMESPACE}" --timeout=120s
kubectl rollout status deployment/echo-bar -n "${NAMESPACE}" --timeout=120s

echo "Waiting for ingress controller to observe new configuration..."
sleep 15

read -r HOST_IP HOST_PORT < <(detect_ingress_endpoint)

echo "Validating ingress routing via ${HOST_IP}:${HOST_PORT}..."

FOO_RESP=$(curl -sS --retry 5 --retry-delay 3 --max-time 5 \
  -H "Host: foo.localhost" "http://${HOST_IP}:${HOST_PORT}/")
BAR_RESP=$(curl -sS --retry 5 --retry-delay 3 --max-time 5 \
  -H "Host: bar.localhost" "http://${HOST_IP}:${HOST_PORT}/")

echo "foo.localhost response: ${FOO_RESP}"
echo "bar.localhost response: ${BAR_RESP}"

if [[ "${FOO_RESP}" != "foo" ]]; then
  echo "Unexpected response from foo.localhost"
  exit 1
fi

if [[ "${BAR_RESP}" != "bar" ]]; then
  echo "Unexpected response from bar.localhost"
  exit 1
fi

echo "Ingress and deployments are healthy."
