# caliban-operator (Helm chart)

The caliban-operator (kube-rs) controller. It watches `CalibanTask` custom
resources cluster-wide and reconciles each into a sandboxed caliband pod (an
agent-sandbox `Sandbox`) with a per-task least-privilege ServiceAccount and a
default-deny NetworkPolicy. See caliban-operator ADR 0002.

## Prerequisites

1. **`CalibanTask` CRD** — install the sibling `caliban-crds` chart first (CRDs
   are installed as their own step).
2. **agent-sandbox** — the `agents.x-k8s.io/v1beta1` `Sandbox` CRD + controller
   must be present in the cluster (a cluster prerequisite; the umbrella can bundle
   it).
3. **Operator image** — a published `caliban-operator` container image reachable
   by the cluster (set `image.repository`/`image.tag`).

## Install

```sh
helm install caliban-crds     ../caliban-crds        # CRDs first (own step)
helm install caliban-operator .                       # then the operator
```

## What it grants

The chart creates a `ServiceAccount` and a `ClusterRole`/`ClusterRoleBinding`
granting the operator exactly what it needs: `get/list/watch/update/patch` on
`calibantasks` (+ `calibantasks/status`), and full management of `sandboxes`
(`agents.x-k8s.io`), `serviceaccounts`, and `networkpolicies`. Leader-election
leases RBAC is available but **off by default** (`leaderElection.enabled`); the
operator runs a single replica today. The caliband pods the operator creates get
their own token-less per-task ServiceAccount with **no** bound Role.

## Cluster-agnostic

Ships generic defaults only. Provide environment specifics via a private values
overlay (`-f private-values.yaml`). Never commit cluster-specific hostnames, IPs,
storage classes, or secrets here.
