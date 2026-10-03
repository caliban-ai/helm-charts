# caliban-system (umbrella chart)

Composes the caliban-ai system on Kubernetes. It wires the per-app charts and
installs them together.

## What it composes

| Subchart | App version | Default |
|----------|-------------|---------|
| `agent-sandbox` (vendored v0.5.0) | v0.5.0 | **on** |
| `gonzalo` | 0.7.0 | **on** |
| `prospero` | 0.8.1 | **on** |
| `caliban-crds` | 0.2.5 | off |
| `caliban-operator` | 0.6.0 | off |
| `ariel` | 0.3.0 | off |

The default install is the **infra tier**: agent-sandbox + gonzalo + prospero.
`caliban-crds` and `caliban-operator` are off together (the operator is useless
without its CRDs) — enable both to run agents in-cluster. `ariel` is off because
it does nothing without Discord and service credentials.

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

### prosperod will not start without an API-auth decision

prospero >= 0.8.0 authenticates its API, and the pod binds `0.0.0.0`, so
**prosperod exits at startup unless you configure tokens or opt out**. Every
install of this umbrella must do one of:

```sh
# Recommended: an existing Secret holding the tokens file
kubectl -n caliban create secret generic prospero-api-tokens \
  --from-literal=tokens="dashboard admin sha256:<hex>"
helm install caliban-system charts/caliban-system \
  --set prospero.apiAuth.tokensSecret.name=prospero-api-tokens

# …or explicitly run with no API auth (anyone who reaches the pod owns the fleet)
helm install caliban-system charts/caliban-system \
  --set prospero.apiAuth.insecureNoAuth=true
```

Generate token lines with `prospero token new <name> --scope read|operate|admin`.
See the [prospero chart README](../prospero/README.md#api-authentication-prospero--080)
for scopes, rotation and how to roll the pod when the Secret changes. The
`deploy-gate` and `reconcile-gate` CI jobs mint a throwaway tokens Secret the
same way — `test/integration/level2.sh` is the worked example.

### Full system (agents in-cluster)

```sh
helm install caliban-system charts/caliban-system \
  --set caliban-crds.enabled=true \
  --set caliban-operator.enabled=true \
  --set prospero.apiAuth.tokensSecret.name=prospero-api-tokens \
  -f my-private-values.yaml
```

Add `--set prospero.fleetBackend=k8s` so the dashboard drives the operator's
`CalibanTask`/`Workspace` CRs rather than looking for local Unix sockets.

## After install

```sh
# prospero dashboard:
kubectl port-forward svc/caliban-system-prospero 7878:7878
# → http://localhost:7878/   (sign in with a token when apiAuth is configured)
```

## Prerequisites

- A default StorageClass (or set one per-app in your overlay) for the PVCs.
- **agent-sandbox is bundled** (`agent-sandbox.enabled`, default `true`) — it is
  not a separate cluster prerequisite unless you choose to bring your own, in
  which case set `agent-sandbox.enabled=false`. See the repo README.
- **No cert-manager requirement:** when the operator is enabled the chart mints
  the caliband session-plane token + TLS cert itself (Helm-generated,
  lookup-preserved across `helm upgrade`). GitOps renderers that run
  `helm template` with no cluster access (e.g. Argo CD) can't `lookup`, so they
  regenerate the creds every sync — such deployments should instead provision the
  session-plane Secrets out-of-band (a cert-manager Certificate + a SealedSecret
  token, using the shared `global.sessionPlane` names) and leave
  `sessionPlane.enabled` unset.
- A prospero API-auth decision before `prospero.enabled` (default `true`) comes
  up — see above.

## Cluster-agnostic

Ships only generic, public defaults — no cluster identifiers (hostnames, IPs,
storage classes, secrets). Environment specifics come from your private overlay.
The `ghcr.io/caliban-ai/*` images are public, so no `imagePullSecrets` are needed.
