#!/usr/bin/env bash
set -euo pipefail
# Fail if any environment-specific identifier leaks into the public charts.
# Charts MUST be cluster-agnostic. Scans deployable chart content only (excludes *.md docs).
#
# Built-in checks: RFC1918 private IPs and *.local hostnames.
# To ALSO deny your own cluster's hostnames/domains WITHOUT committing them to
# this public repo, supply extra regexes privately via either:
#   - env var CHART_DENY_PATTERNS   (one regex per line), or
#   - a gitignored file .chart-deny-extra   (one regex per line; '#' comments ok)
targets='charts/'
fail=0
grepc () { grep -rInE --exclude='*.md' --exclude-dir=.git "$1" $targets 2>/dev/null; }
check () { # regex label [allow-regex]
  local hits
  hits=$(grepc "$1" || true)
  # An optional 3rd arg whitelists matches that are generic, not environment-specific.
  [ -n "${3:-}" ] && hits=$(printf '%s\n' "$hits" | grep -vE "$3" || true)
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits"
    echo "::error::cluster-specific value ($2) found in charts/ — charts must be cluster-agnostic"
    fail=1
  fi
}
check '\b10\.[0-9]+\.[0-9]+\.[0-9]+\b'                 'RFC1918 10.0.0.0/8'
check '\b192\.168\.[0-9]+\.[0-9]+\b'                   'RFC1918 192.168.0.0/16'
check '\b172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+\b' 'RFC1918 172.16.0.0/12'
# `.local` mDNS hostnames — but NOT the reserved Kubernetes cluster domain
# `cluster.local`, a universal, non-environment-specific default that recurs in
# any chart generating service FQDNs.
check '[a-z0-9-]+\.local\b'                            '.local hostname'           '\bcluster\.local\b'
# private extra deny-list (never committed to this public repo)
extra=""
[ -n "${CHART_DENY_PATTERNS:-}" ] && extra+=$'\n'"${CHART_DENY_PATTERNS}"
[ -f .chart-deny-extra ] && extra+=$'\n'"$(cat .chart-deny-extra)"
while IFS= read -r pat; do
  [ -z "$pat" ] && continue
  case "$pat" in \#*) continue ;; esac
  check "$pat" 'private deny-list'
done <<< "$extra"
if [ "$fail" -ne 0 ]; then echo "Leakage guard FAILED."; exit 1; fi
echo "Leakage guard passed: no cluster-specific identifiers in charts/."
