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
| `autostart` | `false` | `--no-autostart` (no caliband in this image) |
| `leaseTtlSecs` | `30` | clustered lease TTL |
| `env` | `{}` | extra raw env vars (map of `name: value`) |
| `resources` | `{}` | pod resource requests/limits |
| `nodeSelector` | `{}` | |
| `tolerations` | `[]` | |
| `affinity` | `{}` | |

`PROSPERO_REPLICA_ID` is set from the pod name automatically. Schema is created
on boot (no migration job). Postgres is never shipped by this chart.

**Cluster-agnostic:** neutral defaults only; supply DB URL / storageClass /
ingress via a private overlay. Never commit cluster-specific values here.
