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
3. **`caliban-crds` >= 0.2.5** — older CRDs make the API server prune
   `CalibanTask.spec.task.permissionPosture` and
   `Workspace.spec.agentPolicy.allowUnattended`, which v0.6.0 reads.

The operator image is public: `ghcr.io/caliban-ai/caliban-operator` is the chart's
default `image.repository` and `image.tag` defaults to `.Chart.AppVersion`
(currently `0.6.0`), so neither needs setting and no `imagePullSecrets` are
required.

## Install

```sh
helm install caliban-crds     ../caliban-crds        # CRDs first (own step)
helm install caliban-operator .                       # then the operator
```

## The caliband image it runs

`env.calibandImage` is the agent runtime the operator starts inside each Sandbox
(`CALIBAND_IMAGE`). It is pinned in `values.yaml` and is deliberately **not** the
same thing as this chart's `appVersion` — the operator and the agent are released
separately. See the comment above the value for the current pin and why.

## What it grants

The chart creates a `ServiceAccount` and a `ClusterRole`/`ClusterRoleBinding`
granting the operator exactly what it needs: `get/list/watch/update/patch` on
`calibantasks` (+ `calibantasks/status`); `get/list/watch` on `workspaces` (+
status write, to resolve `workspaceRef` and report readiness — it never
creates/deletes Workspaces); `get` on `secrets` (validating provider
`credentialsRef` existence — the operator is the **only** component with Secret
read access); full management of `sandboxes` (`agents.x-k8s.io`),
`serviceaccounts`, and `networkpolicies`; and `create`/`patch` on
`events` (`events.k8s.io`), which v0.5.0 needs to emit Kubernetes Events for
reconcile outcomes. Leader-election
leases RBAC is available but **off by default** (`leaderElection.enabled`); the
operator runs a single replica today. The caliband pods the operator creates get
their own token-less per-task ServiceAccount with **no** bound Role.

## Per-session permission posture (v0.6.0)

`CalibanTask.spec.task.permissionPosture` is `supervised` (the default) or
`unattended`. An `unattended` task is admitted only under a `Workspace` whose
`agentPolicy.allowUnattended` is true; otherwise the task fails closed with
`PostureNotPermitted` **before any pod is created**. The posture is echoed on
`status.permissionPosture` and in a `Posture` printer column. Because write access
to a `Workspace` is what authorizes unattended agents, **treat `Workspace` write
access as privileged** (operator ADR 0006).

## Cluster-agnostic

Ships generic defaults only. Provide environment specifics via a private values
overlay (`-f private-values.yaml`). Never commit cluster-specific hostnames, IPs,
storage classes, or secrets here.
