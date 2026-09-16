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
| `auth.existingSecret.name` | `""` | existing Secret holding the principals TOML; `""` = auth off (open) |
| `auth.existingSecret.key` | `principals.toml` | key within that Secret |
| `persistence.storageClass` | `""` | `""` = cluster default |
| `persistence.size` | `1Gi` | |
| `persistence.accessMode` | `ReadWriteOnce` | |
| `env` | `{}` | extra raw env vars (map of name: value) |
| `resources` | `{}` | |
| `nodeSelector` | `{}` | |
| `tolerations` | `[]` | |
| `affinity` | `{}` | |

## Auth: namespace-scoped principals

gonzalod authorizes each request against **principals**: a bearer token with
per-namespace `read` / `write` lists, where `"*"` means every namespace (gonzalo
ADR 0015). The chart keeps them out of values. Put a principals TOML in a Secret
you manage (e.g. a SealedSecret) and name it:

    auth:
      existingSecret:
        name: gonzalo-principals
        key: principals.toml

The chart mounts that key read-only at `/etc/gonzalo/auth/principals.toml` and
sets `GONZALO_AUTH_FILE` to it. With no `existingSecret.name` it renders no auth
configuration and gonzalod runs **open**: any pod that can reach it can read or
write any record.

The old `auth.token` value (one plaintext admin token rendered from values) is
**removed**; setting it now fails the render rather than silently running open.

Example principals file. Generate each token with something like
`openssl rand -base64 32`, and give every client its own:

```toml
# Operators / replication: read and write every namespace. Admin (`*` in both
# lists) is also required for purge and for an unscoped list.
[[principal]]
name  = "admin"
token = "<random>"
read  = ["*"]
write = ["*"]

# Ariel: fleet access-control records (gonzalo ADR 0022). `fleet` holds people,
# identity bindings, role grants, channel config and link tokens; `fleet-audit`
# holds the audit trail.
[[principal]]
name  = "ariel"
token = "<random>"
read  = ["fleet", "fleet-audit"]
write = ["fleet", "fleet-audit"]

# caliban agents: memory and sessions, both in the `caliban` namespace. No
# `fleet` write, so an agent cannot grant itself fleet roles (ariel ADR 0008).
[[principal]]
name  = "caliban-agents"
token = "<random>"
read  = ["caliban"]
write = ["caliban"]

# An auditor or dashboard that only reads the audit trail.
[[principal]]
name  = "fleet-auditor"
token = "<random>"
read  = ["fleet-audit"]
```

gonzalod stamps every authenticated write with the principal's `name` as author,
so a client cannot forge authorship.

**Before turning auth on:** every client configured for remote storage needs a
token, or it gets 401s. For caliban that means any settings file with
`storage.substrate = "remote"` must also set `storage.remote.token_env`, and that
variable must hold the client's token. Health probes are plain TCP connects and
stay unauthenticated.

## HA is a follow-on, not shipped here

Multi-replica HA over an S3-compatible object store (Garage) requires upstream
daemon work that does not exist yet: runtime S3-substrate selection, an
HTTP health endpoint, and conditional writes (**gonzalo #5**). Until those land,
this chart is single-replica fs-backed. See the k8s design spec, gonzalo §5.

**Cluster-agnostic:** ship generic defaults only; supply storageClass and the
principals Secret name via a private overlay (`-f private-values.yaml`). Never
commit cluster-specific values or tokens here.
