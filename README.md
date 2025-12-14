# Goodnotes DevOps Assignment (Senior Implementation)

This repository demonstrates how a seasoned DevOps engineer might approach a small‑scale Kubernetes proof‑of‑concept.  The underlying objective remains unchanged from the original assignment – stand up two `http‑echo` services in a KinD cluster, expose them through an NGINX ingress controller and exercise them with a load test – but the implementation has been hardened, parameterised and documented to reflect production‑grade patterns.

On every pull request targeting `main` a multi‑node KinD cluster is spun up from scratch, the `foo` and `bar` echo deployments are applied, an ingress is configured and a randomised load test is executed.  The resulting Markdown report is posted back on the pull request for visibility.

## Requirements

- Docker (KinD backend)
- `kubectl`
- `kind`
- Bash‑compatible shell (Linux, macOS, or WSL2)
- Internet access to fetch the NGINX ingress manifest and the [`hey`](https://github.com/rakyll/hey) binary

> On WSL2 the scripts auto‑detect the control‑plane IP and ingress NodePort.  In other environments the default host binding is `127.0.0.1:80`.  You can override both values via `KIND_INGRESS_HOST` / `KIND_INGRESS_PORT` if necessary.

## Repository Layout

| Path | Purpose |
| --- | --- |
| **`kind/cluster-config.yaml`** | KinD cluster definition with one control‑plane and two worker nodes.  Ports 80/443 are mapped to the host and a label marks the control‑plane as ingress‑ready. |
| **`k8s/namespace.yaml`** | Defines the `http-echo` namespace and applies descriptive labels for observability and organisation. |
| **`k8s/deploy-foo.yaml`** | Deployment and service manifest for the `foo` instance.  Includes resource requests/limits, readiness/liveness probes and standardised labels. |
| **`k8s/deploy-bar.yaml`** | Deployment and service manifest for the `bar` instance, mirroring the `foo` configuration. |
| **`k8s/ingress.yaml`** | NGINX ingress that routes `foo.localhost` and `bar.localhost` to their respective services. |
| **`scripts/lib.sh`** | Shared Bash utilities for resolving the repository root and discovering the ingress endpoint in a portable way. |
| **`scripts/deploy.sh`** | Orchestrates the application of all manifests, waits for resources to become ready and performs a smoke test via `curl`. |
| **`scripts/loadtest.sh`** | Installs the `hey` load generator on demand, performs randomised load tests against each host and writes a Markdown report.  Concurrency and request ranges can be overridden via environment variables. |
| **`.github/workflows/ci.yml`** | GitHub Actions workflow that provisions a KinD cluster, deploys the workloads, runs the load test and comments the report on pull requests. |
| **`loadtest-report.md`** | Latest load‑test output (generated automatically). |

## Local Walkthrough

1. **Create the KinD cluster**

   ```bash
   # create a cluster named ci-cluster using the supplied configuration
   kind create cluster --name ci-cluster --config kind/cluster-config.yaml
   kubectl get nodes -o wide
   ```

2. **Install ingress-nginx**

   ```bash
   kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml
   kubectl wait --namespace ingress-nginx \
     --for=condition=ready pod \
     --selector=app.kubernetes.io/component=controller \
     --timeout=180s
   ```

3. **Deploy workloads and validate ingress**

   ```bash
   chmod +x scripts/deploy.sh
   ./scripts/deploy.sh
   ```

   The `deploy.sh` script applies all manifests in the `k8s/` directory, waits for the deployments to become available, auto‑detects the ingress endpoint and performs a smoke test to ensure that `foo.localhost` returns `foo` and `bar.localhost` returns `bar`.

4. **Run the load test**

   ```bash
   chmod +x scripts/loadtest.sh
   ./scripts/loadtest.sh       # optional path for the report as the first argument
   ```

   `scripts/loadtest.sh` installs `hey` if it is not already present, randomises request counts (200–350) and concurrency (5–20) for each host and records throughput, average latency, percentile latencies and error counts in a Markdown report.  You can override the ranges by setting `REQUESTS_MIN`, `REQUESTS_MAX`, `CONCURRENCY_MIN` and `CONCURRENCY_MAX` environment variables before invoking the script.

5. **Inspect the report**

   ```bash
   cat loadtest-report.md
   ```

6. **Cleanup**

   ```bash
   kind delete cluster --name ci-cluster
   ```

## CI Pipeline (GitHub Actions)

The [`ci.yml`](.github/workflows/ci.yml) workflow is triggered on every pull request targeting `main`.  It performs the following steps:

1. **Check out the code** using `actions/checkout@v4`.
2. **Install the required tools** (`kubectl` via `azure/setup-kubectl@v4` and `kind` via a simple `curl`/`chmod`/move sequence).
3. **Create a multi‑node KinD cluster** based on the configuration in `kind/cluster-config.yaml`.
4. **Install the NGINX ingress controller** and wait until it becomes ready.
5. **Deploy the workloads and validate ingress** by running `scripts/deploy.sh`.
6. **Run the load test** by invoking `scripts/loadtest.sh` and capture the resulting `loadtest-report.md`.
7. **Comment the report on the pull request** using the `peter‑evans/create‑or‑update‑comment` action.  This makes the results visible directly in the PR discussion without anyone having to inspect workflow artefacts.

You can monitor the workflow run under the PR’s **Checks** tab.  The Markdown report is posted as a comment on the pull request for convenience.

## Implementation Notes

- **Ingress endpoint discovery** prefers explicit environment overrides (`KIND_INGRESS_HOST` / `KIND_INGRESS_PORT`), falls back to the KinD host‑port mapping (`127.0.0.1:80`), and detects the control‑plane container IP plus node port on WSL2.  See `scripts/lib.sh` for details.
- **Load generation** uses [`hey`](https://github.com/rakyll/hey) to keep the solution lightweight; concurrency and request totals are randomised per run to simulate uneven traffic.  You can override the ranges via environment variables.
- **Shell script conventions**: all scripts begin with `set -euo pipefail` to abort on any error or unset variable.  They source `scripts/lib.sh` for shared helpers and are structured into functions for readability.  Temporary directories are cleaned up via `trap` to avoid leaking files.
- **Resource limits and health probes** are defined on each deployment to reflect a more realistic production setup.

## Future Enhancements 

- Replace the raw ingress manifest with a Helm chart for easier upgrades and configuration management.
- Introduce observability (e.g. Prometheus + Grafana) and surface resource usage metrics alongside the load‑test report.
- Emit structured (JSON) load‑test results to enable automated SLO checks and historical comparisons.
