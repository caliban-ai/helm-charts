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
| `charts/caliban-system` | **umbrella** — composes the three above into a full-system install |
| `charts/caliban-crds` | CRD install step (see its README — CRDs are installed separately) |

Each app chart is independently installable; the umbrella wires them together.
**[agent-sandbox](https://agent-sandbox.sigs.k8s.io) is a cluster prerequisite**,
not bundled here.

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
