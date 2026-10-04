# Agent Sandbox Helm Chart

This Helm chart installs the Agent Sandbox controller, which manages `Sandbox` resources on Kubernetes.
CRDs are bundled in the `crds/` directory and are installed automatically by Helm before any other resources.

> **VENDORED, not upstream.** This is a copy of
> [kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox)'s
> `helm/` chart at **v1.0.5**, with batteries-included defaults added (a pinned
> `image.tag`, sane resources) so the `caliban-system` umbrella can ship it
> default-on. Paths below are **this repo's**, not upstream's. On a re-sync, copy
> upstream `helm/` over `charts/agent-sandbox/` and re-apply the provenance header
> in `Chart.yaml`, the defaults in `values.yaml`, and this note.
>
> Re-syncing is not a tag bump — it changes the CRDs the operator's `Sandbox`
> objects are validated against, so it needs the repo's Level 3 `reconcile-gate`
> to prove the operator↔agent-sandbox path still works. Do not raise `image.tag`
> without re-vendoring the CRDs to match.
>
> In practice you install this through the umbrella
> (`helm install caliban-system charts/caliban-system`), which already enables it;
> the standalone commands below are for installing it on its own.

## Installation

### Basic install

```bash
helm install agent-sandbox charts/agent-sandbox \
  --namespace agent-sandbox-system \
  --create-namespace
```

`image.tag` defaults to `v1.0.5` (the vendored chart version) — pass
`--set image.tag=<version>` only to override it.

### Install with extensions enabled

Extensions add support for `SandboxWarmPool`, `SandboxTemplate`, and `SandboxClaim` resources.

```bash
helm install agent-sandbox charts/agent-sandbox \
  --namespace agent-sandbox-system \
  --create-namespace \
  --set controller.extensions=true
```

Through the umbrella, that is `--set agent-sandbox.controller.extensions=true`.

### Install into an existing namespace

```bash
helm install agent-sandbox charts/agent-sandbox \
  --namespace my-namespace \
  --set namespace.create=false \
  --set namespace.name=my-namespace
```

## Upgrading

```bash
helm upgrade agent-sandbox charts/agent-sandbox \
  --namespace agent-sandbox-system \
  --reuse-values \
  --set image.tag=<new-version>
```

> **Note**: Helm does not upgrade CRDs placed in `crds/` automatically. To update CRDs manually after a chart version bump, apply them directly:
>
> ```bash
> kubectl apply -f charts/agent-sandbox/crds/
> ```

### Upgrading from v1alpha1

Support for the `v1alpha1` API has been removed. If you are upgrading from an older release that uses `v1alpha1`, you must upgrade to a `v0.5.x` release and run the storage migration first. Note that this upgrade inverts the general order above: you must apply the `v1beta1` CRDs **before** running `helm upgrade` to prevent conversion errors during webhook service teardown. See the [Helm Upgrade Ordering section in `docs/api-migration-guide.md`](https://github.com/kubernetes-sigs/agent-sandbox/blob/v1.0.5/docs/api-migration-guide.md#helm-upgrade-ordering) for the full sequence.

This chart vendors v1.0.5, which serves `v1beta1` only, so a **fresh install needs no
migration**. Upgrading an existing cluster does have two prerequisites — the
`status.storedVersions` check and the orphaned webhook objects Helm leaves behind;
both are written out in the repo README's agent-sandbox section.

## Uninstallation

```bash
helm uninstall agent-sandbox --namespace agent-sandbox-system
```

> **Note**: Helm does not delete CRDs on uninstall. To remove all CRDs and their associated custom resources:
>
> ```bash
> kubectl delete -f charts/agent-sandbox/crds/
> ```
>
> Warning: This will delete **all** `Sandbox`, `SandboxWarmPool`, `SandboxTemplate`, and `SandboxClaim` objects across all namespaces.

## Configuration

The following table lists the configurable parameters and their defaults. For flag details and recommended profiles at high scale, see [`docs/configuration.md`](https://github.com/kubernetes-sigs/agent-sandbox/blob/v1.0.5/docs/configuration.md) and [`docs/performance-tuning.md`](https://github.com/kubernetes-sigs/agent-sandbox/blob/v1.0.5/docs/performance-tuning.md).

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.tag` | Controller image tag (vendored default; upstream leaves this empty and required) | `v1.0.5` |
| `image.repository` | Controller image repository | `registry.k8s.io/agent-sandbox/agent-sandbox-controller` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `imagePullSecrets` | List of image pull secrets (e.g. `[{name: my-secret}]`) to add to the Deployment | `[]` |
| `replicaCount` | Number of controller replicas | `1` |
| `namespace.create` | Create the namespace as part of the release | `true` |
| `namespace.name` | Namespace to deploy into | `agent-sandbox-system` |
| `controller.leaderElect` | Enable leader election | `true` |
| `controller.leaderElectionNamespace` | Namespace for the leader election resource (auto-detected if empty) | `""` |
| `controller.clusterDomain` | Kubernetes cluster domain for service FQDN generation | `"cluster.local"` |
| `controller.kubeApiQps` | Client-side QPS limit for the Kubernetes API client (`-1` = unlimited) | `-1.0` |
| `controller.kubeApiBurst` | Burst limit for the Kubernetes API client | `10` |
| `controller.apiConnections` | Number of independent HTTP/2 connections to `kube-apiserver` for non-watch traffic | unset (controller default `1`) |
| `controller.separateWatchConnection` | Give the manager's informer cache (list/watch streams) a dedicated HTTP/2 connection | unset (controller default `false`) |
| `controller.sandboxConcurrentWorkers` | Max concurrent reconciles for the Sandbox controller | unset (controller default `100`) |
| `controller.cacheLabelSelectors` | Scope Pod and Service informer caches to sandbox-labeled objects | unset (controller default `false`) |
| `controller.disableSandboxEvents` | Disable Kubernetes `Event` emission from the Sandbox controller | unset (controller default `false`) |
| `controller.sandboxWriteBehindWindow` | Coalescing window for recoverable metadata-only writes on Sandbox objects (`0` disables) | unset (controller default `0s`) |
| `controller.sandboxClaimConcurrentWorkers` | Max concurrent reconciles for the SandboxClaim controller (extensions only) | unset (controller default `50`) |
| `controller.sandboxWarmPoolConcurrentWorkers` | Max concurrent reconciles for the SandboxWarmPool controller (extensions only) | `1` |
| `controller.sandboxTemplateConcurrentWorkers` | Max concurrent reconciles for the SandboxTemplate controller (extensions only) | `1` |
| `controller.sandboxWarmPoolMaxBatchSize` | Max batch size for parallel sandbox create/delete in the SandboxWarmPool controller (extensions only) | `300` |
| `controller.sandboxWarmPoolReplenishDelay` | Defer replacement sandbox creation after warm pool members drop out during claim bursts (extensions only) | unset (controller default `0s`) |
| `controller.sandboxWarmPoolMaxRefillRate` | Max rate (sandboxes/second, per pool) for warm pool replenishment (`0` = unpaced, extensions only) | unset (controller default `0`) |
| `controller.sandboxWarmPoolReadinessGracePeriod` | How long a warm pool sandbox may stay non-Ready before it is considered stuck and replaced, or held if unschedulable (extensions only) | unset (controller default `5m`) |
| `controller.sandboxWarmPoolUnschedulableRecheckInterval` | Re-check interval for pools holding unschedulable sandboxes past the readiness grace period (extensions only) | unset (controller default `1m`) |
| `controller.enableWarmPoolEviction` | Mark pods created by a warm pool as safe to evict (extensions only) | `true` |
| `controller.disableClaimEvents` | Disable Kubernetes `Event` emission from the SandboxClaim controller (extensions only) | unset (controller default `false`) |
| `controller.disableClaimObservabilityAnnotations` | Skip persisting SandboxClaim observability annotations to save one API write per claim (extensions only) | unset (controller default `false`) |
| `controller.enableTracing` | Enable OpenTelemetry tracing via OTLP | `false` |
| `controller.enablePprof` | Enable CPU profiling endpoint on the metrics server | `false` |
| `controller.enablePprofDebug` | Enable all pprof endpoints (implies enablePprof) | `false` |
| `controller.pprofBlockProfileRate` | Block profile sampling rate when pprof debug is enabled | `1000000` |
| `controller.pprofMutexProfileFraction` | Mutex contention sampling rate when pprof debug is enabled | `10` |
| `controller.extraArgs` | Additional flags not listed above (e.g. zap logging flags) | `[]` |
| `controller.extensions` | Enable extensions controller (WarmPool, Template, Claim) | `false` |
| `resources` | CPU/memory resource requests and limits (vendored homelab default; upstream ships `{}`) | `requests: 10m/64Mi`, `limits: 128Mi` |
| `nodeSelector` | Node selector for the controller pod | `{}` |
| `tolerations` | Tolerations for the controller pod | `[]` |
| `affinity` | Affinity rules for the controller pod | `{}` |
| `podSecurityContext` | Pod `securityContext`; only rendered when set (e.g. Kyverno / Pod Security) | `null` |
| `containerSecurityContext` | Container `securityContext` for the controller; only rendered when set | `null` |
| `podAnnotations` | Annotations added to the controller pod template (e.g. service-mesh sidecar toggles, Prometheus scrape autodiscovery) | `{}` |
| `podLabels` | Extra labels added to the controller pod template alongside the chart's selector labels (selector labels take precedence on conflict) | `{}` |
| `service.name` | Name of the controller Service that exposes the metrics endpoint | `agent-sandbox-controller` |
| `metrics.serviceMonitor.enabled` | Create a Prometheus Operator `ServiceMonitor` for the controller metrics endpoint (requires the prometheus-operator CRDs) | `false` |
| `metrics.serviceMonitor.additionalLabels` | Extra labels on the `ServiceMonitor` (often required to match the Prometheus `serviceMonitorSelector`, e.g. `release: kube-prometheus-stack`) | `{}` |
| `metrics.serviceMonitor.interval` | Scrape interval | `30s` |
| `metrics.serviceMonitor.scrapeTimeout` | Scrape timeout (omitted unless set) | `""` |
| `metrics.prometheusRule.enabled` | Create a Prometheus Operator `PrometheusRule` for the controller metrics endpoint (requires the prometheus-operator CRDs) | `false` |
| `metrics.prometheusRule.additionalLabels` | Extra labels on the `PrometheusRule` (often required to match the Prometheus `ruleSelector`, e.g. `release: kube-prometheus-stack`) | `{}` |
| `metrics.prometheusRule.additionalGroups` | Additional Prometheus rule groups appended after the chart's starter rule group | `[]` |

## Metrics

The controller serves Prometheus metrics over HTTP at `:8080/metrics` (exposed by the controller `Service` on the `metrics` port).

To let the Prometheus Operator both scrape the controller and load the chart's starter alerting rule, enable the bundled `ServiceMonitor` and `PrometheusRule`:

```bash
helm install agent-sandbox charts/agent-sandbox \
  --namespace agent-sandbox-system \
  --create-namespace \
  --set metrics.serviceMonitor.enabled=true \
  --set metrics.prometheusRule.enabled=true \
  --set metrics.serviceMonitor.additionalLabels.release=kube-prometheus-stack \
  --set metrics.prometheusRule.additionalLabels.release=kube-prometheus-stack
```

> **Note**: The `ServiceMonitor` and `PrometheusRule` kinds are provided by the prometheus-operator CRDs (`monitoring.coreos.com/v1`). Enabling either one without those CRDs installed will fail at apply time.
>
> The bundled `PrometheusRule` starter set is intentionally small and is most useful once scrape discovery is configured via the chart `ServiceMonitor` or an equivalent Prometheus configuration.

## Development

This chart is vendored, so it is not regenerated here. Upstream generates the CRDs in
`crds/` and the controller-gen rules in `templates/rbac.generated.yaml` and
`templates/extensions-rbac.generated.yaml` from the `//go:generate` directives in
[`codegen.go`](https://github.com/kubernetes-sigs/agent-sandbox/blob/v1.0.5/codegen.go); upstream's `make fix-go-generate` and
`dev/tools/verify-chart-version` do not exist in this repo. To change any of it, re-sync
from upstream rather than editing the generated files in place.
