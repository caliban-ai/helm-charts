# helm-charts

[![ci](https://github.com/caliban-ai/helm-charts/actions/workflows/ci.yml/badge.svg)](https://github.com/caliban-ai/helm-charts/actions/workflows/ci.yml)
[![license: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)

Helm charts for deploying the **caliban-ai** system on Kubernetes.

> **Status:** all six charts are implemented and exercised by CI against a live
> k3s cluster, up to and including a `CalibanTask` reconciling into a Ready
> sandbox pod (the `reconcile-gate` job). See [Testing](#testing).
> Umbrella epic: **caliban-ai/caliban#274**.

## Layout

| Chart | Deploys | App version | Project site |
|-------|---------|-------------|--------------|
| `charts/gonzalo` | gonzalo persistence daemon (`gonzalod`) | 0.7.0 | [gonzalo](https://caliban-ai.github.io/gonzalo/) |
| `charts/prospero` | prospero control plane (`prosperod`) + dashboard | 0.8.1 | [prospero](https://caliban-ai.github.io/prospero/) |
| `charts/caliban-operator` | the kube-rs operator (`CalibanTask` controller) | 0.6.0 | — |
| `charts/ariel` | Ariel chat bridge (`arield`); umbrella default off | 0.3.0 | [ariel](https://caliban-ai.github.io/ariel/) |
| `charts/caliban-crds` | CRD install step (see its README — CRDs are installed separately) | 0.2.9 | — |
| `charts/agent-sandbox` | vendored [agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox) v1.0.5 (Sandbox CRDs + controller) | v1.0.5 | — |
| `charts/caliban-system` | **umbrella** — composes the above into a full-system install | — | — |

The agent runtime itself (`caliband`, from
[caliban](https://caliban-ai.github.io/caliban/)) has no chart: the operator runs
it as a container inside each sandbox, pinned by
`caliban-operator.env.calibandImage`.

Each app chart is independently installable; the umbrella wires them together.

## How the system wires together

```
Discord ──► arield ──HTTP + SSE──► prosperod ──TLS + token──► caliband
              │                        │                   (in a Sandbox pod)
              │                        │                          ▲
              │                        └── CalibanTask CRs ────────┤
              │                                         caliban-operator
              └──────────── records ────────► gonzalod ◄───────────┘
```

- **`gonzalod`** is the record store for everything durable: agent memory and
  sessions (`caliban` namespace) and Ariel's fleet access-control records
  (`fleet` / `fleet-audit`).
- **`prosperod`** is the control plane and dashboard. With
  `prospero.fleetBackend=k8s` it reads and edits `CalibanTask` and `Workspace`
  CRs, so the dashboard drives the operator's agents, and it dials each
  `caliband` over the session plane (TLS + bearer token).
- **`caliban-operator`** reconciles each `CalibanTask` into an agent-sandbox
  `Sandbox` running `caliband`, with a per-task ServiceAccount and a default-deny
  NetworkPolicy.
- **`arield`** is the chat bridge: it takes Discord commands, calls prosperod's
  API to spawn/kill/inspect agents, and keeps its own access-control state in
  gonzalod. It is **off by default** in the umbrella — it needs credentials
  before it does anything.

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

Image repositories are the one exception: `ghcr.io/caliban-ai/{gonzalo,prospero,
caliban-operator,ariel}` are **public**, so the charts default to them and no
`imagePullSecrets` are needed.

## Testing

Four CI jobs, all required:

| Job | Tier | What it proves |
|-----|------|----------------|
| `lint` | 0 | leakage guard, `helm lint` on every chart, `kubeconform` on rendered manifests |
| `integration` | 1 | charts **apply** to a live API server; `CalibanTask` round-trips its CRD schema; operator + prospero RBAC is sufficient (no images needed) |
| `deploy-gate` | 2 | the full umbrella reaches **Ready** on k3s (public images, no registry secrets) |
| `reconcile-gate` | 3 | a `CalibanTask` **reconciles** into a Ready sandbox pod — the operator↔agent-sandbox↔caliband path end to end |

Levels 1–3 run on k3s in CI and identically against any throwaway cluster
locally. See [`test/integration/README.md`](test/integration/README.md) for the
test-tier rationale and how to run each one.

## License

AGPL-3.0-only.
