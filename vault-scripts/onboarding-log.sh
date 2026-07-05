#!/usr/bin/env bash
# onboarding-log.sh — structured, append-only onboarding telemetry.
#
# Source this file, then call:  olog <step> <rc> [k=v ...]
#   step : install | bootstrap | setup | backfill | verify | ...
#   rc   : command exit code — 0 = ok (emitted as "ok":true), nonzero = "ok":false
#   k=v  : extra fields (numeric values stay unquoted; e.g. sessions_indexed=42)
#
# One JSON line per call → ~/vault/logs/onboarding.jsonl, so a NEW USER's onboarding
# trajectory and failures are inspectable locally (`tail`), surfaced by
# `verify-setup.sh --json`, and shipped to the maintainer via `infra-health`.
# Never fails its caller — degrades to a no-op if it can't write.
: "${ONBOARDING_LOG:=$HOME/vault/logs/onboarding.jsonl}"

olog() {
  local step="${1:-unknown}" rc="${2:-0}"
  shift 2 2>/dev/null || true
  local ok; [ "$rc" = 0 ] && ok=true || ok=false
  local extra="" kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"; v="${v//\"/}"
    if [[ "$v" =~ ^-?[0-9]+$ ]]; then extra+=",\"$k\":$v"; else extra+=",\"$k\":\"$v\""; fi
  done
  mkdir -p "$(dirname "$ONBOARDING_LOG")" 2>/dev/null || return 0
  printf '{"ts":"%s","step":"%s","ok":%s%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$step" "$ok" "$extra" >> "$ONBOARDING_LOG" 2>/dev/null || true
}
