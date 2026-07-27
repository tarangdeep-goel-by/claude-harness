#!/usr/bin/env bash
set -uo pipefail

HOOKS_LOG="$HOME/vault/logs/hooks.jsonl"
LOCK_FILE="/tmp/codex-qmd-refresh.lock"
COOLDOWN_SECS=300

mkdir -p "$(dirname "$HOOKS_LOG")"

log_hook() {
  local outcome="$1"
  local detail="${2:-}"
  printf '{"ts":"%s","hook":"codex-qmd-refresh","outcome":"%s","detail":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$outcome" "$detail" >> "$HOOKS_LOG"
}

if ! command -v qmd >/dev/null 2>&1; then
  log_hook "skip" "qmd missing"
  exit 0
fi

if [ -f "$LOCK_FILE" ]; then
  NOW="$(date +%s)"
  LAST="$(cat "$LOCK_FILE" 2>/dev/null || echo 0)"
  if [ $((NOW - LAST)) -lt "$COOLDOWN_SECS" ]; then
    log_hook "skip" "cooldown"
    exit 0
  fi
fi

date +%s > "$LOCK_FILE"

if qmd update >/dev/null 2>&1 && qmd embed >/dev/null 2>&1; then
  log_hook "ok" "qmd update && qmd embed"
else
  log_hook "warn" "qmd refresh failed"
fi
