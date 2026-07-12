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
WORKSPACE_CRD="workspaces.caliban.caliban-ai.dev"

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
  kubectl delete crd "$CRD" "$WORKSPACE_CRD" --ignore-not-found >/dev/null 2>&1 || true
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
  # The CalibanTask CRD has a FIXED cluster-scoped name across all releases, so it
  # is the one object that collides on the next install. Helm's uninstall teardown
  # of it is async/version-dependent — purge it deterministically before moving on.
  kubectl delete crd "$CRD" "$WORKSPACE_CRD" --ignore-not-found --wait >/dev/null 2>&1 || true
}
smoke gonzalo  gonzalo          caliban-l1-gonzalo
smoke prospero prospero         caliban-l1-prospero
smoke op       caliban-operator caliban-l1-operator
smoke crds     caliban-crds     caliban-l1-crds
# `update` (not `build`) regenerates Chart.lock from Chart.yaml and vendors every
# dependency — including agent-sandbox, which the umbrella bundles by default. It
# works offline for the file:// local subcharts, so no registry access is needed.
helm dependency update "$CHARTS/caliban-system" >/dev/null 2>&1 || true
# Full default stack: agent-sandbox is default-on; also turn on the operator + CRDs.
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
#      and NOT what it must not?
#      Uses raw SubjectAccessReview objects with explicit group/resource/verb
#      strings — the apiserver authorizer evaluates those against RBAC directly,
#      with NO discovery. This is what lets us assert `sandboxes.agents.x-k8s.io`
#      and `calibantasks` even though neither CRD is installed at Level 1.
#      (`kubectl auth can-i` is NOT usable here: it resolves the resource through
#      discovery first and silently answers "no" for any unregistered type.)
echo "══ 3. operator RBAC sufficiency (SubjectAccessReview, discovery-free) ══"
kubectl create ns caliban-l1-rbac >/dev/null 2>&1 || true
helm install oponly "$CHARTS/caliban-operator" -n caliban-l1-rbac >/dev/null
SA=$(kubectl -n caliban-l1-rbac get sa -l app.kubernetes.io/name=caliban-operator \
       -o jsonpath='{.items[0].metadata.name}')
SUBJ="system:serviceaccount:caliban-l1-rbac:${SA}"
can_i() { # group resource verb [subresource]  -> prints "true"/"false"
  kubectl create -o jsonpath='{.status.allowed}' -f - 2>/dev/null <<EOF
apiVersion: authorization.k8s.io/v1
kind: SubjectAccessReview
spec:
  user: ${SUBJ}
  resourceAttributes:
    group: ${1}
    resource: ${2}
    verb: ${3}
    subresource: ${4:-}
EOF
}
label() { printf '%s %s%s (%s)' "$3" "$2" "${4:+/$4}" "${1:-core}"; }
allow() { # group resource verb [subresource] — expect allowed
  if [ "$(can_i "$@")" = "true" ]; then ok "allowed: $(label "$@")"
  else bad "DENIED (should allow): $(label "$@") — RBAC insufficient"; fi
}
deny() {  # group resource verb — negative control, expect denied
  if [ "$(can_i "$@")" = "true" ]; then bad "ALLOWED (should deny): $(label "$@") — over-broad"
  else ok "correctly denied: $(label "$@")"; fi
}
for v in get list watch update patch; do allow caliban.caliban-ai.dev calibantasks "$v"; done
for v in get update patch; do allow caliban.caliban-ai.dev calibantasks "$v" status; done
# Workspace: the operator resolves CalibanTask.workspaceRef (get/list/watch) and
# writes Workspace status (validation/readiness) — but never creates/deletes them.
for v in get list watch; do allow caliban.caliban-ai.dev workspaces "$v"; done
for v in get update patch; do allow caliban.caliban-ai.dev workspaces "$v" status; done
for v in get list watch create update patch delete; do allow agents.x-k8s.io sandboxes "$v"; done
for v in get list watch create update patch delete; do allow "" serviceaccounts "$v"; done
for v in get list watch create update patch delete; do allow networking.k8s.io networkpolicies "$v"; done
allow "" secrets get                              # reads credentialsRef Secrets (existence check) — sole Secret reader
deny caliban.caliban-ai.dev calibantasks delete   # operator has no delete on its own CR
deny caliban.caliban-ai.dev workspaces create     # prospero owns Workspace CRUD, not the operator
deny caliban.caliban-ai.dev workspaces delete     # ditto
deny "" pods create                               # operator makes Sandboxes, never pods directly
deny "" secrets list                              # gets credentialsRef Secrets by name only, never lists
helm uninstall oponly -n caliban-l1-rbac >/dev/null 2>&1 || true

echo "──────────────────────────────"
printf 'result: \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
