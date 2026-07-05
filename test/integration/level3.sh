#!/usr/bin/env bash
# Level 3 reconcile gate for the caliban-ai Helm charts.
# Brings the full umbrella up (like Level 2), applies a CalibanTask, and asserts the
# operator reconciles it end-to-end into a RUNNING sandboxed caliband pod
# (CalibanTask.status.phase == Running). This is the deepest tier: it requires the
# caliband image (ghcr.io/caliban-ai/caliban) to be published AND the operator's
# reconcile path to work — so it stays red until both are true, by design.
#
# On failure it dumps where the reconcile stalled: the CalibanTask status, the
# agent-sandbox Sandbox the operator should have created, the backing pod, and the
# operator's own logs.
#
# Usage:  KUBECONFIG=/path/to/kubeconfig test/integration/level3.sh
#   LEVEL3_DEPLOY_TIMEOUT=6m     umbrella Ready wait (default 6m)
#   LEVEL3_RECONCILE_TIMEOUT=4m  CalibanTask -> Running wait (default 4m)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHARTS="$ROOT/charts"
FIXTURES="$ROOT/test/integration/fixtures"
REL=caliban-system
NS=caliban
SANDBOX_NS=agent-sandbox-system
CR=l1-valid   # metadata.name in calibantask-valid.yaml
DEPLOY_TIMEOUT="${LEVEL3_DEPLOY_TIMEOUT:-6m}"
RECONCILE_TIMEOUT="${LEVEL3_RECONCILE_TIMEOUT:-4m}"

log() { printf '\033[36m%s\033[0m\n' "$*"; }

cleanup() {
  log "── cleanup ──"
  kubectl -n "$NS" delete -f "$FIXTURES/calibantask-valid.yaml" --ignore-not-found >/dev/null 2>&1 || true
  helm uninstall "$REL" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete ns "$NS" "$SANDBOX_NS" --wait=false --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

dump() {
  echo "### ❌ Level 3 gate FAILED — CalibanTask did not reconcile to Running"
  echo
  echo '```'
  echo "== CalibanTask $NS/$CR (status) =="
  kubectl -n "$NS" get calibantask "$CR" \
    -o jsonpath='  phase=[{.status.phase}]{"\n"}  conditions={.status.conditions}{"\n"}' 2>&1
  echo "  (empty phase => the operator never got far enough to set status; see operator logs)"
  echo
  echo "== agent-sandbox Sandboxes (the operator should have created one) =="
  kubectl get sandboxes.agents.x-k8s.io -A 2>&1
  echo
  echo "== operator logs (tail 50) =="
  kubectl -n "$NS" logs "deploy/${REL}-caliban-operator" --tail=50 2>&1 | sed 's/^/  /'
  echo
  echo "== pods (caliban + agent-sandbox) =="
  kubectl get pods -A -o wide 2>&1 | grep -E 'NAMESPACE|caliban|agent-sandbox'
  for ns in "$NS" "$SANDBOX_NS"; do
    for p in $(kubectl -n "$ns" get pods -o name 2>/dev/null); do
      ready=$(kubectl -n "$ns" get "$p" \
                -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
      [ "$ready" = "True" ] && continue
      echo
      echo "== NOT READY: $ns/$p =="
      kubectl -n "$ns" describe "$p" 2>&1 | awk '/^Events:/{f=1} f'
      echo "  -- logs (tail 30) --"
      kubectl -n "$ns" logs "$p" --tail=30 --all-containers 2>&1 | sed 's/^/    /'
    done
  done
  echo '```'
}

# ── 1. bring the umbrella up (a failure here is an L2-level regression, not L3) ──
log "vendoring umbrella dependencies…"
helm dependency update "$CHARTS/$REL" >/dev/null 2>&1 || \
  helm dependency build "$CHARTS/$REL" >/dev/null 2>&1 || true

log "installing full umbrella + waiting up to $DEPLOY_TIMEOUT for Ready…"
if ! helm install "$REL" "$CHARTS/$REL" \
       --namespace "$NS" --create-namespace \
       --set caliban-crds.enabled=true --set caliban-operator.enabled=true \
       --wait --timeout "$DEPLOY_TIMEOUT"; then
  log "❌ umbrella did not reach Ready — this is a Level 2 regression, not a reconcile failure"
  { dump; } | { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && tee -a "$GITHUB_STEP_SUMMARY" || cat; }
  exit 1
fi

# ── 2. apply a CalibanTask and ask the operator to reconcile it ──
log "applying CalibanTask $CR and waiting up to $RECONCILE_TIMEOUT for status.phase=Running…"
kubectl apply -n "$NS" -f "$FIXTURES/calibantask-valid.yaml" >/dev/null

if kubectl -n "$NS" wait --for=jsonpath='{.status.phase}'=Running \
      --timeout="$RECONCILE_TIMEOUT" "calibantask/$CR" 2>/dev/null; then
  log "✅ Level 3 PASS — CalibanTask reconciled to a running sandboxed pod"
  exit 0
fi

# ── 3. failure path: show where the reconcile stalled ──
phase=$(kubectl -n "$NS" get calibantask "$CR" -o jsonpath='{.status.phase}' 2>/dev/null)
log "❌ Level 3 FAIL — CalibanTask did not reach Running (last phase: ${phase:-<unset>})"
{ dump; } | { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && tee -a "$GITHUB_STEP_SUMMARY" || cat; }
exit 1
