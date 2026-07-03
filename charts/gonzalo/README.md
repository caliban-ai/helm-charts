# gonzalo (Helm chart)

Deploys the gonzalo persistence daemon (`gonzalod`), HTTP + gRPC, as a
single-replica StatefulSet using the **filesystem substrate** on a PVC.

## Install

    helm install gonzalo charts/gonzalo \
      --set image.repository=ghcr.io/caliban-ai/gonzalo

## Values

| Key | Default | Notes |
|-----|---------|-------|
| `replicaCount` | `1` | fs substrate = single writer (see HA note) |
| `image.repository` | `""` | required at install |
| `image.tag` | `""` | defaults to `.Chart.AppVersion` |
| `service.type` | `ClusterIP` | |
| `service.httpPort` | `8080` | HTTP/JSON |
| `service.grpcPort` | `50051` | gRPC |
| `auth.token` | `""` | if set, enforced as `GONZALO_TOKEN` via a Secret |
| `persistence.storageClass` | `""` | `""` = cluster default |
| `persistence.size` | `1Gi` | |
| `persistence.accessMode` | `ReadWriteOnce` | |
| `env` | `{}` | extra raw env vars (map of name: value) |
| `resources` | `{}` | |
| `nodeSelector` | `{}` | |
| `tolerations` | `[]` | |
| `affinity` | `{}` | |

## HA is a follow-on, not shipped here

Multi-replica HA over an S3-compatible object store (Garage) requires upstream
daemon work that does not exist yet: runtime S3-substrate selection, an
HTTP health endpoint, and conditional writes (**gonzalo #5**). Until those land,
this chart is single-replica fs-backed. See the k8s design spec, gonzalo §5.

**Cluster-agnostic:** ship generic defaults only; supply storageClass / token
via a private overlay (`-f private-values.yaml`). Never commit
cluster-specific values here.
