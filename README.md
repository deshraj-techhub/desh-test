# Goodnotes DevOps Assignment

Automated end-to-end validation for dual `http-echo` workloads on KinD. Every pull request to `main` provisions a multi-node cluster, deploys the `foo` and `bar` services behind ingress, runs randomized HTTP load, and comments the results back on the PR.

## Requirements
- Docker (KinD backend)
- `kubectl`
- `kind`
- Bash-compatible shell (Linux, macOS, or WSL2)
- Internet access to fetch the nginx ingress manifest and the `hey` binary

> On WSL2 the scripts auto-detect the control-plane IP and ingress NodePort. In other environments the default host binding is `127.0.0.1:80`. Override via `KIND_INGRESS_HOST` / `KIND_INGRESS_PORT` if necessary.

## Repository Layout
- `kind/cluster-config.yaml`: KinD cluster (1 control plane, 2 workers, hostPorts 80/443)
- `k8s/*.yaml`: namespace, deployments, services, and ingress for `foo`/`bar`
- `scripts/lib.sh`: shared helpers (repo root resolution, ingress endpoint detection)
- `scripts/deploy.sh`: applies manifests, waits for readiness, validates ingress responses
- `scripts/loadtest.sh`: installs `hey`, runs randomized load, writes `loadtest-report.md`
- `.github/workflows/ci.yml`: GitHub Actions pipeline that executes the full flow and comments the report on PRs
- `loadtest-report.md`: latest load-test output (generated)

## Local Walkthrough
1. **Create the KinD cluster**
  ```bash
  kind create cluster --name ci-cluster --config kind/cluster-config.yaml
  kubectl get nodes -o wide
  ```

2. **Install ingress-nginx**
  ```bash
  kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml
  kubectl wait -n ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=180s
  ```

3. **Deploy workloads and validate ingress**
  ```bash
  chmod +x scripts/deploy.sh
  ./scripts/deploy.sh
  ```
  The script applies all manifests, waits for both deployments to become available, auto-detects the ingress endpoint, and verifies `foo.localhost` → `foo`, `bar.localhost` → `bar`.

4. **Run the load test**
  ```bash
  chmod +x scripts/loadtest.sh
  ./scripts/loadtest.sh       # optional output path as first arg
  ```
  `scripts/loadtest.sh` installs `hey` if missing, randomizes request count (200–350) and concurrency (5–20) per host, and records throughput, latency (avg/P90/P95), and error counts in Markdown.

5. **Inspect the report**
  ```bash
  cat loadtest-report.md
  ```

6. **Cleanup**
  ```bash
  kind delete cluster --name ci-cluster
  ```

## CI Pipeline (GitHub Actions)
- Triggers on every `pull_request` event targeting `main`
- Installs `kubectl` and KinD, then provisions the multi-node cluster defined in `kind/cluster-config.yaml`
- Applies ingress-nginx and waits for the controller to report ready
- Runs `scripts/deploy.sh` and `scripts/loadtest.sh`
- Uploads `loadtest-report.md` and posts the contents as a PR comment via `create-or-update-comment`

You can review the workflow run under the PR’s **Checks** tab, and the Markdown report appears in the PR conversation thread.

## Implementation Notes
- Ingress endpoint discovery prefers explicit environment overrides, falls back to the KinD hostPort mapping (`127.0.0.1:80`), and detects the control-plane container IP + NodePort on WSL2.
- Load generation uses `hey` to keep the solution simple; concurrency and request totals are randomized per run to simulate uneven traffic splits.
- Both automation scripts abort on failure (`set -euo pipefail`) so CI halts immediately if any validation step fails.

## Time Spent
`~5 hours total (1h planning, 1.5h cluster/manifests, 1h CI wiring, 1.5h validation + docs)`

## Future Enhancements
- Replace the raw ingress manifest with a Helm chart for easier upgrades
- Add Prometheus + Grafana (or another observability stack) and surface resource metrics alongside the load-test report
- Emit structured (JSON) load-test results to enable automated SLO checks and historical comparisons
# desh-test
