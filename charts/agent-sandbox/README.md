# Agent Sandbox Helm Chart

This Helm chart installs the Agent Sandbox controller, which manages `Sandbox` resources on Kubernetes.
CRDs are bundled in the `crds/` directory and are installed automatically by Helm before any other resources.

> **VENDORED, not upstream.** This is a copy of
> [kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox)'s
> `helm/` chart at **v0.5.0**, with batteries-included defaults added (a pinned
> `image.tag`, sane resources) so the `caliban-system` umbrella can ship it
> default-on. Paths below are **this repo's**, not upstream's. On a re-sync, copy
> upstream `helm/` over `charts/agent-sandbox/` and re-apply the provenance header
> in `Chart.yaml`, the defaults in `values.yaml`, and this note.
>
> **Upstream has since reached v1.0.x.** Re-syncing is not a tag bump: it changes
> the CRD schemas the operator's `Sandbox` objects are validated against, so it
> needs the repo's Level 3 `reconcile-gate` to prove the operator↔agent-sandbox
> path still works. Do not raise `image.tag` without re-vendoring the CRDs to match.
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

`image.tag` defaults to `v0.5.0` (the vendored chart version) — pass
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

### v1alpha1 → v1beta1 storage migration

Upgrades to chart versions that move CRDs from `v1alpha1` to `v1beta1` require a
manual storage migration. The vendored copy of upstream's script is
[`files/migrate.sh`](files/migrate.sh).

See upstream's
[API migration guide](https://github.com/kubernetes-sigs/agent-sandbox/blob/main/docs/api-migration-guide.md)
for full details, sequence of steps, and operational guidelines. (This chart
already ships `v1beta1` CRDs, so a fresh install needs no migration.)

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

The following table lists the configurable parameters and their defaults.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.tag` | Controller image tag (vendored default; upstream leaves this empty and required) | `v0.5.0` |
| `image.repository` | Controller image repository | `registry.k8s.io/agent-sandbox/agent-sandbox-controller` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `replicaCount` | Number of controller replicas | `1` |
| `namespace.create` | Create the namespace as part of the release | `true` |
| `namespace.name` | Namespace to deploy into | `agent-sandbox-system` |
| `controller.leaderElect` | Enable leader election | `true` |
| `controller.leaderElectionNamespace` | Namespace for the leader election resource (auto-detected if empty) | `""` |
| `controller.clusterDomain` | Kubernetes cluster domain for service FQDN generation | `"cluster.local"` |
| `controller.kubeApiQps` | Client-side QPS limit for the Kubernetes API client (`-1` = unlimited) | `-1.0` |
| `controller.kubeApiBurst` | Burst limit for the Kubernetes API client | `10` |
| `controller.sandboxConcurrentWorkers` | Max concurrent reconciles for the Sandbox controller | `1` |
| `controller.sandboxClaimConcurrentWorkers` | Max concurrent reconciles for the SandboxClaim controller (extensions only) | `1` |
| `controller.sandboxWarmPoolConcurrentWorkers` | Max concurrent reconciles for the SandboxWarmPool controller (extensions only) | `1` |
| `controller.sandboxTemplateConcurrentWorkers` | Max concurrent reconciles for the SandboxTemplate controller (extensions only) | `1` |
| `controller.enableTracing` | Enable OpenTelemetry tracing via OTLP | `false` |
| `controller.enablePprof` | Enable CPU profiling endpoint on the metrics server | `false` |
| `controller.enablePprofDebug` | Enable all pprof endpoints (implies enablePprof) | `false` |
| `controller.pprofBlockProfileRate` | Block profile sampling rate when pprof debug is enabled | `1000000` |
| `controller.pprofMutexProfileFraction` | Mutex contention sampling rate when pprof debug is enabled | `10` |
| `controller.extraArgs` | Additional flags not listed above (e.g. zap logging flags) | `[]` |
| `controller.extensions` | Enable extensions controller (WarmPool, Template, Claim) | `false` |
| `resources` | CPU/memory resource requests and limits | `{}` |
| `nodeSelector` | Node selector for the controller pod | `{}` |
| `tolerations` | Tolerations for the controller pod | `[]` |
| `affinity` | Affinity rules for the controller pod | `{}` |
| `podSecurityContext` | Pod `securityContext`; only rendered when set (e.g. Kyverno / Pod Security) | `null` |
| `containerSecurityContext` | Container `securityContext` for the controller; only rendered when set | `null` |
| `podAnnotations` | Annotations added to the controller pod template (e.g. service-mesh sidecar toggles, Prometheus scrape autodiscovery) | `{}` |
| `podLabels` | Extra labels added to the controller pod template alongside the chart's selector labels (selector labels take precedence on conflict) | `{}` |
| `webhookServiceName` | Name of the conversion webhook Service | `agent-sandbox-webhook-service` |
