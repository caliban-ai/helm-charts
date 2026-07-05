# Level 1 Live-Cluster Integration Test — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add a CI job that stands up an ephemeral cluster and proves — with no container images and no registry secrets — that the charts *apply* to a real API server, that a `CalibanTask` round-trips through its CRD schema, and that the operator's RBAC is sufficient.

**Architecture:** A single self-contained bash runner (`test/integration/level1.sh`) drives `helm` + `kubectl` against whatever cluster `KUBECONFIG` points at, so it runs identically locally and in CI. It never passes `--wait`, so plain `helm install` applies manifests and returns without needing pods to reach Ready. CI provisions k3s (prod-realistic, light) and calls the script. Each test phase installs → asserts → uninstalls its release, so cluster-scoped objects (the CRD, the operator ClusterRole) never collide across phases.

**Tech Stack:** bash, helm ≥ 3.16, kubectl, k3s (CI), kind (local verification only).

## Global Constraints (copied from ticket #8 / repo rules)

- **No container images, no registry secrets.** The job must pass on a bare cluster; never wait for pod Readiness.
- **Cluster-agnostic.** No cluster-specific identifiers in fixtures or scripts (the `check-no-cluster-leakage.sh` guard runs on `charts/` only, but keep test assets generic too).
- **Charts install on defaults.** `storageClass: ""` = cluster default; umbrella has `caliban-crds`/`caliban-operator` OFF by default (flip both on for the umbrella smoke).
- **CRD identity (verbatim):** name `calibantasks.caliban.caliban-ai.dev`, group `caliban.caliban-ai.dev`, version `v1alpha1`, Namespaced. Required: `spec.task.prompt`, `spec.workspace.sources[].{name,path,repo}`.
- **Operator RBAC matrix (verbatim from `charts/caliban-operator/templates/rbac.yaml`):**
  - `calibantasks` (group `caliban.caliban-ai.dev`): get, list, watch, update, patch
  - `calibantasks/status`: get, update, patch
  - `sandboxes` (group `agents.x-k8s.io`): get, list, watch, create, update, patch, delete
  - `serviceaccounts` (core): get, list, watch, create, update, patch, delete
  - `networkpolicies` (group `networking.k8s.io`): get, list, watch, create, update, patch, delete
- **`auth can-i` is a SubjectAccessReview** (pure RBAC eval, no discovery) → the `sandboxes.agents.x-k8s.io` checks work even though agent-sandbox is *not* installed at Level 1.

## File Structure

- Create: `test/integration/level1.sh` — the runner (apply smoke + CRD round-trip + RBAC).
- Create: `test/integration/fixtures/calibantask-valid.yaml` — minimal schema-valid CR.
- Create: `test/integration/fixtures/calibantask-invalid.yaml` — CR missing required `spec.task.prompt` (must be rejected).
- Create: `test/integration/README.md` — the L0–L3 tier table and why L1 is the line.
- Modify: `.github/workflows/ci.yml` — add the `integration` job (k3s + run script).
- Modify: `README.md` — add a short "Testing" pointer.

---

### Task 1: Test fixtures (valid + invalid CalibanTask)

**Files:**
- Create: `test/integration/fixtures/calibantask-valid.yaml`
- Create: `test/integration/fixtures/calibantask-invalid.yaml`

- [ ] **Step 1: Write the valid fixture**

```yaml
# Minimal schema-valid CalibanTask: satisfies spec.task.prompt and
# spec.workspace.sources[].{name,path,repo}. Generic values only.
apiVersion: caliban.caliban-ai.dev/v1alpha1
kind: CalibanTask
metadata:
  name: l1-valid
spec:
  task:
    prompt: "hello from the level-1 integration test"
  workspace:
    sources:
      - name: caliban
        path: /work/caliban
        repo: https://example.invalid/caliban.git
```

- [ ] **Step 2: Write the invalid fixture (missing required `task.prompt`)**

```yaml
# Invalid on purpose: spec.task is present but omits the required `prompt`.
# The API server must REJECT this on create — proves the CRD schema has teeth.
apiVersion: caliban.caliban-ai.dev/v1alpha1
kind: CalibanTask
metadata:
  name: l1-invalid
spec:
  task: {}
  workspace:
    sources:
      - name: caliban
        path: /work/caliban
        repo: https://example.invalid/caliban.git
```

- [ ] **Step 3: Commit**

```bash
git add test/integration/fixtures/
git commit -m "test(integration): add valid/invalid CalibanTask fixtures for L1"
```

---

### Task 2: The Level 1 runner script

**Files:**
- Create: `test/integration/level1.sh` (chmod +x)

**Interfaces:**
- Consumes: `KUBECONFIG` env; charts under `charts/`; fixtures from Task 1.
- Produces: exit 0 when every assertion passes, exit 1 otherwise; human-readable ✓/✗ lines.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Level 1 live-cluster integration test for the caliban-ai Helm charts.
# Verifies what `helm lint` + kubeconform cannot: real API-server *apply*
# acceptance, CalibanTask CRD<->CR schema round-trip, and operator RBAC
# sufficiency. Needs NO container images and NO registry secrets — it never
# waits for pod Readiness (plain `helm install` applies manifests and returns).
#
# Usage:  KUBECONFIG=/path/to/kubeconfig test/integration/level1.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHARTS="$ROOT/charts"
FIXTURES="$ROOT/test/integration/fixtures"
CRD="calibantasks.caliban.caliban-ai.dev"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '\033[32m  ✓ %s\033[0m\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf '\033[31m  ✗ %s\033[0m\n' "$*"; }

NS=(caliban-l1-gonzalo caliban-l1-prospero caliban-l1-operator caliban-l1-crds \
    caliban-l1-umbrella caliban-l1-cr caliban-l1-rbac)
cleanup() {
  echo "── cleanup ──"
  for r in gonzalo prospero op crds sys crdonly oponly; do
    for ns in "${NS[@]}"; do helm uninstall "$r" -n "$ns" --ignore-not-found >/dev/null 2>&1 || true; done
  done
  kubectl delete crd "$CRD" --ignore-not-found >/dev/null 2>&1 || true
  for ns in "${NS[@]}"; do kubectl delete ns "$ns" --wait=false --ignore-not-found >/dev/null 2>&1 || true; done
}
trap cleanup EXIT

# ── 1. apply smoke: does the API server ACCEPT every chart? (install+uninstall)
echo "══ 1. apply smoke (helm install, no Ready-wait) ══"
smoke() { # release chart ns [extra helm args...]
  local rel="$1" chart="$2" ns="$3"; shift 3
  kubectl create ns "$ns" >/dev/null 2>&1 || true
  local out
  if out=$(helm install "$rel" "$CHARTS/$chart" -n "$ns" --wait=false "$@" 2>&1); then
    ok "helm install $chart accepted by API server"
  else
    bad "helm install $chart REJECTED"; printf '%s\n' "$out" | tail -20 | sed 's/^/      /'
  fi
  helm uninstall "$rel" -n "$ns" --ignore-not-found >/dev/null 2>&1 || true
}
smoke gonzalo  gonzalo          caliban-l1-gonzalo
smoke prospero prospero         caliban-l1-prospero
smoke op       caliban-operator caliban-l1-operator
smoke crds     caliban-crds     caliban-l1-crds
helm dependency build "$CHARTS/caliban-system" >/dev/null 2>&1 || true
smoke sys caliban-system caliban-l1-umbrella \
  --set caliban-crds.enabled=true --set caliban-operator.enabled=true

# ── 2. CRD <-> CR round-trip: is the CRD's own schema usable & enforced?
echo "══ 2. CalibanTask CRD <-> CR round-trip ══"
kubectl create ns caliban-l1-cr >/dev/null 2>&1 || true
helm install crdonly "$CHARTS/caliban-crds" -n caliban-l1-crds >/dev/null
if kubectl wait --for=condition=Established --timeout=60s "crd/$CRD" >/dev/null 2>&1; then
  ok "CRD Established"
else
  bad "CRD never Established"
fi
if kubectl apply -n caliban-l1-cr -f "$FIXTURES/calibantask-valid.yaml" >/dev/null 2>&1; then
  ok "valid CalibanTask accepted"
else
  bad "valid CalibanTask REJECTED (fixture drift vs schema)"
fi
if kubectl apply -n caliban-l1-cr -f "$FIXTURES/calibantask-invalid.yaml" >/dev/null 2>&1; then
  bad "invalid CalibanTask ACCEPTED (schema has no teeth)"
else
  ok "invalid CalibanTask rejected (schema enforced)"
fi
helm uninstall crdonly -n caliban-l1-crds >/dev/null 2>&1 || true
kubectl delete crd "$CRD" --ignore-not-found >/dev/null 2>&1 || true

# ── 3. operator RBAC sufficiency: does the ClusterRole permit what it must,
#      and NOT what it must not? (SubjectAccessReview — no images, no CRDs needed)
echo "══ 3. operator RBAC sufficiency ══"
kubectl create ns caliban-l1-rbac >/dev/null 2>&1 || true
helm install oponly "$CHARTS/caliban-operator" -n caliban-l1-rbac >/dev/null
SA=$(kubectl -n caliban-l1-rbac get sa -l app.kubernetes.io/name=caliban-operator \
       -o jsonpath='{.items[0].metadata.name}')
SUBJ="system:serviceaccount:caliban-l1-rbac:${SA}"
allow() { # verb resource [extra can-i args...]
  if kubectl auth can-i "$1" "$2" --as="$SUBJ" "${@:3}" -q >/dev/null 2>&1; then
    ok "allowed: $1 $2 ${*:3}"
  else
    bad "DENIED (should allow): $1 $2 ${*:3} — RBAC insufficient"
  fi
}
deny() { # verb resource — must be denied (negative control / teeth)
  if kubectl auth can-i "$1" "$2" --as="$SUBJ" -q >/dev/null 2>&1; then
    bad "ALLOWED (should deny): $1 $2 — over-broad or test has no teeth"
  else
    ok "correctly denied: $1 $2"
  fi
}
for v in get list watch update patch; do allow "$v" "calibantasks.caliban.caliban-ai.dev"; done
for v in get update patch; do allow "$v" "calibantasks.caliban.caliban-ai.dev" --subresource=status; done
for v in get list watch create update patch delete; do allow "$v" "sandboxes.agents.x-k8s.io"; done
for v in get list watch create update patch delete; do allow "$v" "serviceaccounts"; done
for v in get list watch create update patch delete; do allow "$v" "networkpolicies.networking.k8s.io"; done
deny delete "calibantasks.caliban.caliban-ai.dev"   # operator has no delete on its own CR
deny create "pods"                                  # operator makes Sandboxes, never pods directly
deny get    "secrets"                               # operator has no secrets access
helm uninstall oponly -n caliban-l1-rbac >/dev/null 2>&1 || true

echo "──────────────────────────────"
printf 'result: \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x test/integration/level1.sh
```

- [ ] **Step 3: Run against an ephemeral local kind cluster (verification)**

Do NOT use the `default` kube-context (that is a live cluster). Create a throwaway kind cluster:

```bash
# install kind into scratchpad if missing, create isolated cluster
kind create cluster --name caliban-l1
KUBECONFIG="$(kind get kubeconfig --name caliban-l1 > /tmp/l1.kubeconfig; echo /tmp/l1.kubeconfig)" \
  test/integration/level1.sh; echo "exit=$?"
```

Expected: every ✓, `result: N passed, 0 failed`, exit 0.

- [ ] **Step 4: Prove teeth — flip a fixture and confirm the suite goes red**

Temporarily add `prompt: "x"` to the invalid fixture, re-run: the "invalid CalibanTask rejected" assertion must flip to ✗ and exit 1. Revert after.

- [ ] **Step 5: Commit**

```bash
git add test/integration/level1.sh
git commit -m "test(integration): add Level 1 runner (apply smoke + CRD round-trip + RBAC can-i)"
```

---

### Task 3: CI job (k3s + run)

**Files:**
- Modify: `.github/workflows/ci.yml` — add an `integration` job alongside `lint`.

- [ ] **Step 1: Add the job**

```yaml
  integration:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: azure/setup-helm@v4
        with:
          version: v3.16.3
      - uses: azure/setup-kubectl@v4
      - name: start k3s (no traefik/servicelb/metrics)
        run: |
          curl -sfL https://get.k3s.io | \
            INSTALL_K3S_EXEC="--disable=traefik --disable=servicelb --disable=metrics-server --write-kubeconfig-mode=644" sh -
          echo "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> "$GITHUB_ENV"
          until kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes 2>/dev/null | grep -q ' Ready'; do
            sleep 2
          done
      - name: level 1 integration test
        run: bash test/integration/level1.sh
```

- [ ] **Step 2: Lint the workflow YAML locally**

```bash
helm template charts/gonzalo >/dev/null   # sanity: repo tools present
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo "yaml ok"
```

Expected: `yaml ok`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add Level 1 integration job (k3s apply/CRD/RBAC)"
```

---

### Task 4: Docs — tier table + pointer

**Files:**
- Create: `test/integration/README.md`
- Modify: `README.md` (add a "Testing" section pointer)

- [ ] **Step 1: Write `test/integration/README.md`**

Contents: the L0–L3 tier table (what each tests, whether it needs images/secrets/agent-sandbox), a statement that L1 is the deliberate line and why, and the local run command (`KUBECONFIG=... test/integration/level1.sh`) with the ephemeral-cluster caveat.

- [ ] **Step 2: Add a Testing pointer to `README.md`**

A short section linking `test/integration/README.md` and noting CI runs Level 1 on k3s.

- [ ] **Step 3: Commit**

```bash
git add test/integration/README.md README.md
git commit -m "docs(test): document integration test tiers (L0-L3) and why L1 is the line"
```

---

## Self-Review

- **Spec coverage:** apply smoke (Task 2 §1, all 5 charts incl. umbrella) ✓; CRD round-trip valid+invalid (Task 2 §2) ✓; RBAC can-i incl. negative controls (Task 2 §3) ✓; no images/secrets (never `--wait`) ✓; green + teeth-proof (Task 2 Steps 3-4) ✓; docs (Task 4) ✓; CI job (Task 3) ✓.
- **Open risk to verify locally:** (a) `auth can-i` on `sandboxes.agents.x-k8s.io` with no CRD installed — confirm it evaluates (expected: yes, SAR is discovery-free). (b) `--subresource=status` can-i syntax on this kubectl. (c) k3s default PodSecurity does not *reject* the chart pods on apply. All three are settled by the Task 2 Step 3 local run before anything is pushed.
