# prospero (Helm chart)

Deploys the prospero control plane (`prosperod`) + dashboard. Two topologies,
selected by `topology`:

- `standalone` — sqlite on a PVC, single replica (StatefulSet). Good for a
  dashboard/history over a local fleet.
- `clustered` — external Postgres, N replicas with leased ownership (Deployment).
  Postgres is a **prerequisite you provide**; supply its URL via a Secret.

## Install — standalone

    helm install prospero charts/prospero \
      --set image.repository=ghcr.io/caliban-ai/prospero

## Install — clustered

    kubectl create secret generic prospero-db --from-literal=url='postgres://…'
    helm install prospero charts/prospero \
      --set image.repository=ghcr.io/caliban-ai/prospero \
      --set topology=clustered --set replicaCount=3 \
      --set database.existingSecret=prospero-db

## Values

| Key | Default | Notes |
|-----|---------|-------|
| `topology` | `standalone` | `standalone` \| `clustered` (anything else fails fast) |
| `replicaCount` | `1` | clustered only |
| `image.repository` | `ghcr.io/caliban-ai/prospero` | the public image; override to pin a fork/mirror |
| `image.tag` | `""` | defaults to `.Chart.AppVersion` when unset |
| `image.pullPolicy` | `IfNotPresent` | |
| `service.port` | `7878` | REST/SSE/dashboard |
| `host` | `local` | `PROSPERO_HOST` fleet *identity* (not the backend — see `fleetBackend`) |
| `fleetBackend` | `local` | `local` (caliband over Unix — empty in a container) \| `k8s` (the config plane: reads/edits `CalibanTask` **and** `Workspace` CRs in this namespace so the dashboard manages the operator's workspaces + agents; needs image ≥ 0.1.1 and adds a Role over `calibantasks` + `workspaces`, with **no** Secret access) |
| `secretPicker.enabled` | `false` | k8s only; when `true`, grants prospero `list` on Secrets (names only, never values) so the dashboard can offer a `credentialsRef` picker. Off by default to keep prospero fully off credential RBAC |
| `persistence.storageClass` | `""` | standalone only; `""` = cluster default. No toggle — the PVC always exists |
| `persistence.size` | `1Gi` | standalone only |
| `persistence.accessMode` | `ReadWriteOnce` | standalone only |
| `database.existingSecret` | `""` | Secret holding the Postgres URL (clustered) |
| `database.secretKey` | `url` | key within that Secret |
| `database.url` | `""` | inline alternative to `existingSecret`; keep out of the public repo, overlay only |
| `apiAuth.tokensSecret.name` / `.key` | `""` / `tokens` | existing Secret holding the tokens file; mounted, `PROSPERO_API_TOKENS_FILE` |
| `apiAuth.sessionKeySecret.name` / `.key` | `""` / `session.key` | existing Secret holding the cookie HMAC key; **required** clustered with tokens |
| `apiAuth.insecureNoAuth` | `false` | `PROSPERO_INSECURE_NO_AUTH=1`: run with no API auth (explicit opt-out) |
| `apiAuth.cookieSecure` | `false` | `PROSPERO_COOKIE_SECURE=1`: always mark the session cookie `Secure` |
| `autostart` | `false` | `--no-autostart` (no caliband in this image) |
| `leaseTtlSecs` | `30` | clustered lease TTL |
| `env` | `{}` | extra raw env vars (map of `name: value`) |
| `resources` | `{}` | pod resource requests/limits |
| `nodeSelector` | `{}` | |
| `tolerations` | `[]` | |
| `affinity` | `{}` | |

## API authentication (prospero >= 0.8.0)

prosperod authenticates its API with named tokens (prospero ADR-0010). The pod
binds `0.0.0.0`, and with no tokens prosperod **refuses to start**, so every
install must choose one of:

- **Tokens (recommended).** Generate one per client and keep the printed token;
  prosperod stores only its hash:

      prospero token new dashboard --scope admin
      # prints the token once, and a tokens-file line: dashboard admin sha256:<hex>

  Put the lines in a Secret (a SealedSecret in GitOps) and name it:

      kubectl create secret generic prospero-api-tokens \
        --from-literal=tokens="dashboard admin sha256:<hex>"
      helm install prospero charts/prospero --set apiAuth.tokensSecret.name=prospero-api-tokens

  Scopes: `read` (every GET), `operate` (+ spawn, kill, input), `admin` (+ workspace
  changes). The dashboard signs in with a token; the CLI uses `PROSPERO_TOKEN`.
  `/healthz` and `/readyz` stay open, so probes need no token.
- **Clustered** additionally needs a shared cookie-signing key
  (`openssl rand -base64 48`) in `apiAuth.sessionKeySecret`, or the render fails.
- **Opt out:** `apiAuth.insecureNoAuth=true`. Anyone who can reach the pod
  controls the fleet.

The chart fails the render only for contradictions (tokens plus `insecureNoAuth`,
or clustered tokens without a session key). With neither set it renders, and
prosperod exits with a message naming both options.

Revoking a token: remove its line from the Secret and restart the pod.

`PROSPERO_REPLICA_ID` is set from the pod name automatically. Schema is created
on boot (no migration job). Postgres is never shipped by this chart.

**Cluster-agnostic:** neutral defaults only; supply DB URL / storageClass /
ingress via a private overlay. Never commit cluster-specific values here.
