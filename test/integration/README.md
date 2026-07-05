# Integration tests

A live-cluster test that exercises what static checks can't. The repo's default
CI (`helm lint` + `kubeconform`) only validates *rendered YAML*; it never applies
a chart to a real API server. This suite does.

## Test tiers

The ladder — Level 1 is a required gate; Level 2 is a **non-blocking deployability
gate** (see below); Level 3 is deferred:

| Level | What it proves | Needs images? | Needs registry secrets? | In CI? |
|-------|----------------|:---:|:---:|:---:|
| **0** | Rendered YAML is schema-valid (`helm lint`, `kubeconform`) | no | no | ✅ required (`lint`) |
| **1** | Charts **apply** to a real API server; `CalibanTask` round-trips its CRD schema; operator **RBAC is sufficient** | no | no | ✅ required (`integration`) |
| **2** | Full umbrella (agent-sandbox + gonzalo + prospero + operator + CRDs) reaches **Ready** on k3s | yes (all **public**) | no | ⚠️ non-blocking (`deploy-gate`) |
| 3 | Full operator **reconcile** (a `CalibanTask` → a sandboxed pod) | yes | yes | ❌ deferred |

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

### Level 2 — the deployability gate

Level 1 proves the manifests are *accepted*; Level 2 proves the umbrella actually
*comes up*. `level2.sh` installs the full `caliban-system` umbrella (agent-sandbox +
gonzalo + prospero + operator + CRDs) with public-image defaults and waits for every
workload to reach Ready (`helm install --wait`). Because CI k3s matches the home
cluster (same distro, default `local-path` storage), **a green run means the umbrella
is safe to deploy to the home cluster** — and the same script runs locally against a
throwaway namespace as a pre-`helm upgrade` check. On failure it dumps which workload
isn't Ready and why (describe / logs / events) to the job log and the step summary.

It uses **only public images** — no registry secrets, no private overlay. The
`deploy-gate` CI job is **`continue-on-error: true`** (non-blocking) so it doesn't
red-wall unrelated PRs while readiness is being driven to green. Promote it to a
required gate by dropping that line once it passes reliably.

**Current status: red — by design, on a real blocker.** The caliban-ai ghcr images
(`gonzalo`, `prospero`, `caliban-operator` at tag `0.1.0`) are not anonymously
pullable: the pull fails with `401 Unauthorized` fetching an anonymous ghcr token.
Making those packages public (or publishing public `0.1.0` tags) is the prerequisite
for this gate to go green. agent-sandbox (`registry.k8s.io`) already pulls and reaches
Ready.

### Why Level 3 stays deferred

Level 3 (operator reconcile) needs the caliband image and a working agent-sandbox
reconcile path — meaningfully more cost and flakiness. Deferred until a concrete
reconcile bug makes it worth that tax.

## How it works

Both `level1.sh` and `level2.sh` drive `helm` + `kubectl` against whatever
`KUBECONFIG` points at, so they run identically locally and in CI. `level2.sh`
installs the full umbrella once and blocks on `helm install --wait` (that is the
whole point — it verifies Readiness), dumping diagnostics if the wait fails.
`level1.sh` never waits for Readiness; its key properties:

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

# Level 1 — apply / CRD / RBAC (fast, no images):
KUBECONFIG=/tmp/l1.kubeconfig test/integration/level1.sh

# Level 2 — full umbrella reaches Ready (pulls public images; ~2m when green):
KUBECONFIG=/tmp/l1.kubeconfig test/integration/level2.sh
#   LEVEL2_TIMEOUT=6m overrides the Ready wait.

kind delete cluster --name caliban-l1
```

Level 1 exits 0 when all assertions pass (`N passed, M failed` tally). Level 2 exits 0
when every umbrella workload reaches Ready, else 1 with a diagnostic dump.
