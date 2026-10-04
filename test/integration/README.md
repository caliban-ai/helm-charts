# Integration tests

A live-cluster test that exercises what static checks can't. The repo's default
CI (`helm lint` + `kubeconform`) only validates *rendered YAML*; it never applies
a chart to a real API server. This suite does.

## Test tiers

The ladder. **All four tiers are required gates in CI** — a red at any level
blocks merge:

| Level | What it proves | Needs images? | Needs registry secrets? | In CI? |
|-------|----------------|:---:|:---:|:---:|
| **0** | Rendered YAML is schema-valid (`helm lint`, `kubeconform`) | no | no | ✅ required (`lint`) |
| **1** | Charts **apply** to a real API server; `CalibanTask` round-trips its CRD schema; operator + prospero **RBAC is sufficient** | no | no | ✅ required (`integration`) |
| **2** | Full umbrella (agent-sandbox + gonzalo + prospero + operator + CRDs) reaches **Ready** on k3s | yes (all **public**) | no | ✅ required (`deploy-gate`) |
| **3** | Operator **reconciles** a `CalibanTask` → a running sandboxed caliband pod | yes (all **public**) | no | ✅ required (`reconcile-gate`) |

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
  asserts the full cluster-scoped matrix — including a few negative controls the
  operator must be **denied** — using raw `SubjectAccessReview` objects. (Not yet
  covered: the namespaced `leases` Role that `leaderElection.enabled` now renders
  by default. L2/L3 exercise it implicitly, since the operator must take its lease
  before it reconciles anything.)
- **Prospero RBAC sufficiency.** Under `fleetBackend=k8s` prospero gets a
  *namespaced* Role — CalibanTask/Workspace CRUD plus `patch` on
  `calibantasks/status` for the `AgentsSettled` condition. Level 1 asserts it the
  same way, with the review scoped to the release namespace (a Role grants nothing
  to a cluster-scoped review), and denies status `update`, Workspace status writes,
  and Secret access.
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

It uses **only public images** — no registry secrets, no private overlay. It does
create one Secret: prospero >= 0.8.0 refuses to bind `0.0.0.0` without API auth,
so the script mints a throwaway token, hashes it, and installs with
`--set prospero.apiAuth.tokensSecret.name=prospero-api-tokens`. That is the worked
example for any real install (see the prospero chart README).

**Required gate.** The `gonzalo`, `prospero`, and `caliban-operator` ghcr packages are
public and the full umbrella reaches Ready (verified on kind + k3s), so `deploy-gate`
is a blocking gate — a red means the umbrella can no longer be stood up. (History: it
was initially red because those packages defaulted to **private** despite their source
repos being public — ghcr package visibility is independent of repo visibility.)

**What L2 does *not* cover.** It stops short of a reconcile: it never creates a
`CalibanTask`, so the caliband image is never pulled — caliband appears only as the
operator's `CALIBAND_IMAGE` env var, which is consumed at reconcile time. So a green L2
means the umbrella *deploys and comes up*, not that a submitted task *runs*. Proving a
task actually runs (and that `ghcr.io/caliban-ai/caliban` is published) is **Level 3**.

### Level 3 — the reconcile gate

`level3.sh` brings the umbrella up (like L2), applies a `CalibanTask`, and asserts the
operator reconciles it end-to-end in **two** stages: (1) `CalibanTask.status.phase`
reaches **Running** (the operator created the `Sandbox`), then (2) the backing sandbox
pod `<task>-sbx` reaches **Ready** — because `phase=Running` is optimistic (set when the
Sandbox is created, before the pod is healthy), so the real proof of a working task is a
Ready pod (workspace cloned, caliband up). On failure it dumps where the reconcile
stalled: the CalibanTask status, the agent-sandbox `Sandbox`, the backing pod, and the
**operator's own logs**.

**Required gate.** Verified green end-to-end (kind + k3s): `CalibanTask → Sandbox →
pod Ready`. A red here means the operator↔agent-sandbox reconcile path or the
caliband image regressed. The two pins it exercises are the operator chart's
`appVersion` (currently `0.6.0`) and `caliban-operator.env.calibandImage` (the
agent runtime) — this gate is the thing to run before changing either.

**What L3 caught during development.** With the earlier operator (`0.1.0`/`latest`) the
reconcile failed the server-side apply — the operator emitted a `Sandbox` with
`spec.volumeClaimTemplates[].apiVersion`, which the agent-sandbox `Sandbox` schema
rejects (`500: field not declared in schema`) — true of v0.5.0 then, and still true of
the vendored v1.0.5 now. That operator↔agent-sandbox mismatch — a
cross-component break only a live reconcile can surface — was fixed in
caliban-operator#7 and released as `v0.1.1`, which this chart now pins.

## How it works

`level1.sh`, `level2.sh` and `level3.sh` all drive `helm` + `kubectl` against
whatever `KUBECONFIG` points at, so they run identically locally and in CI.
`level2.sh` installs the full umbrella once and blocks on `helm install --wait`
(that is the whole point — it verifies Readiness), dumping diagnostics if the wait
fails. `level3.sh` does the same install, then applies a `Workspace` and a
`CalibanTask` and waits on the reconcile. `level1.sh` never waits for Readiness;
its key properties:

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

# Level 3 — a CalibanTask reconciles into a Ready sandbox pod (slowest tier):
KUBECONFIG=/tmp/l1.kubeconfig test/integration/level3.sh
#   LEVEL3_DEPLOY_TIMEOUT=6m     umbrella Ready wait
#   LEVEL3_RECONCILE_TIMEOUT=4m  CalibanTask -> Running wait
#   LEVEL3_POD_TIMEOUT=3m        sandbox pod -> Ready wait

kind delete cluster --name caliban-l1
```

Level 1 exits 0 when all assertions pass (`N passed, M failed` tally). Level 2 exits 0
when every umbrella workload reaches Ready, else 1 with a diagnostic dump. Level 3
exits 0 when the `CalibanTask` reaches `status.phase=Running` **and** its backing
`<task>-sbx` pod reaches Ready, else 1 with the CalibanTask status, the `Sandbox`,
the pod, and the operator's logs.
