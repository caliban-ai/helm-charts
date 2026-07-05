#!/usr/bin/env bash
# Level 2 deployability gate for the caliban-ai Helm charts.
# Installs the FULL caliban-system umbrella (agent-sandbox + gonzalo + prospero +
# operator + CRDs) and waits for every workload to reach Ready. A green run means
# the umbrella is safe to deploy to the (k3s) home cluster. Uses only PUBLIC images
# — no registry secrets, no private overlay.
#
# On failure it dumps actionable diagnostics (which workload isn't Ready, and why:
# describe / logs / events) so a red gate tells you what to fix.
#
# Usage:  KUBECONFIG=/path/to/kubeconfig test/integration/level2.sh
#   LEVEL2_TIMEOUT=6m  (override the Ready wait; default 6m). When the umbrella is
#   healthy, --wait returns as soon as every workload is Ready (usually ~2m); the
#   full timeout is only consumed while something is genuinely failing to come up.
#
# Deliberately NOT `set -e`: the Ready-wait failure is handled explicitly so we can
# emit diagnostics instead of dying silently.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHARTS="$ROOT/charts"
REL=caliban-system
NS=caliban
SANDBOX_NS=agent-sandbox-system
TIMEOUT="${LEVEL2_TIMEOUT:-6m}"

log() { printf '\033[36m%s\033[0m\n' "$*"; }

cleanup() {
  log "── cleanup ──"
  helm uninstall "$REL" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete ns "$NS" "$SANDBOX_NS" --wait=false --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

# `update` regenerates Chart.lock from Chart.yaml and vendors every file:// subchart
# (incl. agent-sandbox) offline — no registry access needed.
log "vendoring umbrella dependencies…"
helm dependency update "$CHARTS/$REL" >/dev/null 2>&1 || \
  helm dependency build "$CHARTS/$REL" >/dev/null 2>&1 || true

log "installing full umbrella + waiting up to $TIMEOUT for every workload to reach Ready…"
if helm install "$REL" "$CHARTS/$REL" \
      --namespace "$NS" --create-namespace \
      --set caliban-crds.enabled=true --set caliban-operator.enabled=true \
      --wait --timeout "$TIMEOUT"; then
  log "✅ Level 2 PASS — all umbrella workloads reached Ready"
  exit 0
fi

# ── failure path: dump actionable diagnostics ─────────────────────────────────
dump() {
  echo "### ❌ Level 2 gate FAILED — umbrella workloads did not reach Ready in $TIMEOUT"
  echo
  echo '```'
  echo "== workloads =="
  kubectl get deploy,statefulset -A 2>&1 | grep -E 'NAMESPACE|caliban|agent-sandbox'
  echo
  echo "== all pods =="
  kubectl get pods -A -o wide 2>&1 | grep -E 'NAMESPACE|caliban|agent-sandbox'
  for ns in "$NS" "$SANDBOX_NS"; do
    for p in $(kubectl -n "$ns" get pods -o name 2>/dev/null); do
      ready=$(kubectl -n "$ns" get "$p" \
                -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
      [ "$ready" = "True" ] && continue
      echo
      echo "== NOT READY: $ns/$p =="
      kubectl -n "$ns" describe "$p" 2>&1 | awk '/^Events:/{f=1} f'
      echo "  -- logs (current, tail 40) --"
      kubectl -n "$ns" logs "$p" --tail=40 --all-containers 2>&1 | sed 's/^/    /'
      echo "  -- logs (previous, tail 40) --"
      kubectl -n "$ns" logs "$p" --previous --tail=40 --all-containers 2>&1 | sed 's/^/    /'
    done
    echo
    echo "== recent events in $ns =="
    kubectl -n "$ns" get events --sort-by=.lastTimestamp 2>&1 | tail -25
  done
  echo '```'
}

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  dump | tee -a "$GITHUB_STEP_SUMMARY"
else
  dump
fi
exit 1
