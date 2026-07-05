# Integration tests

A live-cluster test that exercises what static checks can't. The repo's default
CI (`helm lint` + `kubeconform`) only validates *rendered YAML*; it never applies
a chart to a real API server. This suite does.

## Test tiers

We deliberately stop at **Level 1**. The ladder:

| Level | What it proves | Needs images? | Needs registry secrets? | Needs agent-sandbox? | In CI? |
|-------|----------------|:---:|:---:|:---:|:---:|
| **0** | Rendered YAML is schema-valid (`helm lint`, `kubeconform`) | no | no | no | ✅ (`lint` job) |
| **1** | Charts **apply** to a real API server; `CalibanTask` round-trips its CRD schema; operator **RBAC is sufficient** | **no** | **no** | **no** | ✅ (`integration` job) |
| 2 | Pods reach **Ready** (probes correct, workloads roll out) | yes | yes (private images) | no | ❌ (deferred) |
| 3 | Full operator **reconcile** (a `CalibanTask` → a sandboxed pod) | yes | yes | yes | ❌ (deferred) |

### Why Level 1 is the line

Level 1 catches the failure classes `kubeconform` structurally cannot, at zero
image/secret cost:

- **CRD schema usability.** CI runs `caliban-crds` through kubeconform with
  `-ignore-missing-schemas` because there is no meta-schema for a
  `CustomResourceDefinition`, and none for a `CalibanTask`. Whether a real
  `CalibanTask` actually conforms to its own CRD's OpenAPI schema is otherwise
  **untested anywhere**. Level 1 installs the CRD, applies a valid CR (must be
  accepted) and an invalid one (must be rejected).
- **Operator RBAC sufficiency.** `caliban-operator` ships a ClusterRole. Nothing
  else checks it actually *permits* the verbs/resources the operator needs. Level 1
  asserts the full matrix — including a few negative controls the operator must be
  **denied** — using raw `SubjectAccessReview` objects.
- **Real apply.** CRD registration, RBAC object creation, admission/defaulting, and
  umbrella dependency wiring all run against a live control plane.

Levels 2–3 add real value (probe correctness, actual reconcile) but drag in
private-registry pull secrets in a **public** repo and, for L3, an `agent-sandbox`
install — meaningfully more cost and flakiness. They are deferred until a concrete
probe/reconcile bug makes them worth that tax.

## How it works

`level1.sh` drives `helm` + `kubectl` against whatever `KUBECONFIG` points at, so it
runs identically locally and in CI. Key properties:

- **No Ready-wait.** Plain `helm install` applies manifests and returns; it never
  blocks on pod Readiness — which is why no container images are needed. Each phase
  installs → asserts → uninstalls, purging the fixed-name `CalibanTask` CRD between
  releases so cluster-scoped objects don't collide.
- **Discovery-free RBAC.** The RBAC phase posts `SubjectAccessReview` objects with
  explicit `group`/`resource`/`verb` strings. The apiserver authorizer evaluates
  those against RBAC directly, with no discovery — so `sandboxes.agents.x-k8s.io`
  and `calibantasks` assert correctly even though **neither CRD is installed**.
  (`kubectl auth can-i` is *not* usable here: it resolves the resource through
  discovery first and silently answers "no" for any unregistered type.)
- **Distro-agnostic.** Level 1 tests API-server behaviors (apply/CRD/RBAC), which are
  conformant across distributions. CI runs it on **k3s**; it is equally valid on
  kind, microk8s, or any real cluster.

## Running locally

Point it at an **ephemeral, throwaway** cluster — never a shared/production one; it
installs a cluster-scoped CRD and ClusterRoles and tears them down.

```sh
# e.g. with kind
kind create cluster --name caliban-l1 --kubeconfig /tmp/l1.kubeconfig
KUBECONFIG=/tmp/l1.kubeconfig test/integration/level1.sh
kind delete cluster --name caliban-l1
```

Exit 0 = all assertions passed; the suite prints a `N passed, M failed` tally.
