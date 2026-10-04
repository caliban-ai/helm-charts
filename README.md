# helm-charts

[![ci](https://github.com/caliban-ai/helm-charts/actions/workflows/ci.yml/badge.svg)](https://github.com/caliban-ai/helm-charts/actions/workflows/ci.yml)
[![license: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)

Helm charts for deploying the **caliban-ai** system on Kubernetes.

> **Status:** repository scaffolding + chart skeletons. Templates land in the
> per-app content tickets. See the umbrella epic **caliban-ai/caliban#274**.

## Layout

| Chart | Deploys |
|-------|---------|
| `charts/gonzalo` | gonzalo persistence daemon (`gonzalod`) |
| `charts/prospero` | prospero control plane (`prosperod`) + dashboard |
| `charts/caliban-operator` | the kube-rs operator (`CalibanTask` controller) |
| `charts/ariel` | Ariel chat bridge (`arield`); umbrella default off |
| `charts/caliban-system` | **umbrella** — composes the below into a full-system install |
| `charts/caliban-crds` | CRD install step (see its README — CRDs are installed separately) |
| `charts/agent-sandbox` | vendored [agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox) v1.0.5 (Sandbox CRDs + controller) |

Each app chart is independently installable; the umbrella wires them together.

### agent-sandbox: bundled by default, or bring your own

The operator composes **agent-sandbox** (the `agents.x-k8s.io/v1beta1` `Sandbox`
CRDs + controller). The umbrella **bundles our preferred install by default**
(`charts/agent-sandbox`, vendored from kubernetes-sigs/agent-sandbox v1.0.5), so a
default `helm install` of `caliban-system` brings it up alongside the operator.

To **bring your own** agent-sandbox (an existing cluster install), disable the
bundled one:

```sh
helm install caliban-system charts/caliban-system --set agent-sandbox.enabled=false
```

Re-sync the vendored copy on a version bump: copy upstream `helm/` over
`charts/agent-sandbox/` and re-apply the provenance header + defaults (see the
chart's `Chart.yaml`).

#### Upgrading an existing cluster to the v1.0.5 vendoring

agent-sandbox v1.0.0 removed the `v1alpha1` API, the conversion webhook and its TLS
certificates. Two consequences for a cluster that already runs an older install:

1. **The API server rejects the CRD upgrade** unless all four Sandbox CRDs already
   report only `v1beta1` in `status.storedVersions`. Check before upgrading — if
   `v1alpha1` is still listed, run the v0.5.x storage migration first (upstream's
   [API migration guide](https://github.com/kubernetes-sigs/agent-sandbox/blob/v1.0.5/docs/api-migration-guide.md)):

   ```sh
   kubectl get crd sandboxes.agents.x-k8s.io \
     sandboxclaims.extensions.agents.x-k8s.io \
     sandboxtemplates.extensions.agents.x-k8s.io \
     sandboxwarmpools.extensions.agents.x-k8s.io \
     -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.storedVersions}{"\n"}{end}'
   ```

2. **Four webhook objects are left orphaned** — the chart no longer renders them, and
   Helm does not delete resources it has stopped rendering when a subchart is
   upgraded in place. Remove them after the upgrade:

   ```sh
   kubectl delete -n agent-sandbox-system \
     svc/agent-sandbox-webhook-service \
     secret/agent-sandbox-webhook-certs \
     role/agent-sandbox-controller \
     rolebinding/agent-sandbox-controller \
     --ignore-not-found
   ```

Note also that Helm never upgrades CRDs in a chart's `crds/` directory. GitOps engines
that render with `helm template --include-crds` (Argo CD does) apply them normally; a
plain `helm upgrade` needs `kubectl apply -f charts/agent-sandbox/crds/` first.

## Cluster-agnostic by rule (this repo is public)

Charts ship **only generic, sane defaults** — **no cluster-specific identifiers**
(hostnames, domains, IPs, storage classes, ingress classes, node selectors,
secrets). Supply environment specifics from a **separate private values overlay**
at deploy time:

```sh
helm install caliban-system charts/caliban-system -f /path/to/private-values.yaml
```

A CI **leakage guard** (`scripts/check-no-cluster-leakage.sh`) fails the build if
a cluster-specific identifier or private IP appears in `charts/`.

## Testing

Beyond `helm lint` + `kubeconform` (static, in the `lint` CI job), a **Level 1
live-cluster test** (`integration` CI job, on k3s) proves the charts *apply* to a
real API server, that a `CalibanTask` round-trips its CRD schema, and that the
operator's RBAC is sufficient — with no container images and no registry secrets.
See [`test/integration/README.md`](test/integration/README.md) for the test-tier
rationale and how to run it locally.

## License

AGPL-3.0-only.
