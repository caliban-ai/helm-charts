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
| `charts/caliban-crds` | CRD install step (see its README — CRDs are installed separately) | 0.2.5 | — |
| `charts/agent-sandbox` | vendored [agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox) v0.5.0 (Sandbox CRDs + controller) | v0.5.0 | — |
| `charts/caliban-system` | **umbrella** — composes the above into a full-system install | — | — |

The agent runtime itself (`caliband`, from
[caliban](https://caliban-ai.github.io/caliban/)) has no chart: the operator runs
it as a container inside each sandbox, pinned by
`caliban-operator.env.calibandImage`.

Each app chart is independently installable; the umbrella wires them together.

## How the system wires together

```
Discord ──► arield ──HTTP──► prosperod ──HTTP+SSE──► caliband (in a Sandbox pod)
              │                  │                        ▲
              │                  └── CalibanTask CRs ──────┤
              │                                 caliban-operator
              └──────────── records ──────► gonzalod ◄─────┘
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
(`charts/agent-sandbox`, vendored from kubernetes-sigs/agent-sandbox v0.5.0), so a
default `helm install` of `caliban-system` brings it up alongside the operator.

To **bring your own** agent-sandbox (an existing cluster install), disable the
bundled one:

```sh
helm install caliban-system charts/caliban-system --set agent-sandbox.enabled=false
```

Re-sync the vendored copy on a version bump: copy upstream `helm/` over
`charts/agent-sandbox/` and re-apply the provenance header + defaults (see the
chart's `Chart.yaml`).

> **Vendored version is behind upstream.** We vendor **v0.5.0**; upstream has
> since reached **v1.0.x**. Re-syncing is not a tag bump — it changes the CRDs
> the operator's `Sandbox` objects are validated against, so it needs the
> `reconcile-gate` (Level 3) to prove the operator↔agent-sandbox path still
> works. Tracked separately; do not bump the pin in `values.yaml` alone.

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
