# caliban-system (umbrella chart)

Composes the caliban-ai system on Kubernetes. It wires the per-app charts and
installs them together.

## Status

**M1 — infra umbrella (current):** deploys **gonzalo** (persistence) and
**prospero** (control plane + dashboard) — both use the published public images
`ghcr.io/caliban-ai/{gonzalo,prospero}`. `caliban-operator` is **disabled** by
default; it arrives in P2 (agent-sandbox + `CalibanTask`), after which no-agents
becomes agents-sandboxed.

## Install

```sh
# 1. Build subchart dependencies (they are gitignored; CI/you regenerate them):
helm dependency build charts/caliban-system

# 2. Install with your private, cluster-specific overlay:
helm install caliban-system charts/caliban-system -f my-private-values.yaml
```

Start from [`example-values.yaml`](example-values.yaml) — copy it to a private
file and fill in your cluster's `storageClass`, sizes, resources, and (for
prospero HA) the Postgres secret. **Never commit your filled-in overlay** — this
repo is cluster-agnostic by rule (a CI leakage guard enforces it).

## After install

```sh
# prospero dashboard:
kubectl port-forward svc/caliban-system-prospero 7878:7878
# → http://localhost:7878/
```

## Prerequisites

- A default StorageClass (or set one per-app in your overlay) for the PVCs.
- For the full system later (P2): **[agent-sandbox](https://agent-sandbox.sigs.k8s.io)**
  installed as a cluster prerequisite (it is not bundled here).

## Cluster-agnostic

Ships only generic, public defaults — no cluster identifiers (hostnames, IPs,
storage classes, secrets). Environment specifics come from your private overlay.
