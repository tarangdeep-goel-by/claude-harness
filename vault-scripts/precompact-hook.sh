#!/bin/bash
# Claude Code PreCompact hook: export full transcript BEFORE compaction truncates it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPORT_SCRIPT="$SCRIPT_DIR/export-session.py"
PROJECTS_BASE="$HOME/.claude/projects"
HOOKS_LOG="$HOME/vault/logs/hooks.jsonl"
START_TS=$(date +%s)

mkdir -p "$(dirname "$HOOKS_LOG")"

hook_log() {
  local outcome="$1" detail="${2:-}"
  local dur=$(( $(date +%s) - START_TS ))
  printf '{"ts":"%s","hook":"precompact","session":"%s","cwd":"%s","outcome":"%s","detail":"%s","duration_s":%d}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${SESSION_ID:-unknown}" "${SESSION_CWD:-}" "$outcome" "$detail" "$dur" >> "$HOOKS_LOG"
}

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null || true)
SESSION_CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null || true)

find_jsonl() {
  if [ -n "$SESSION_CWD" ] && [ -n "$SESSION_ID" ]; then
    DERIVED_DIR="$PROJECTS_BASE/$(echo "$SESSION_CWD" | tr '/' '-')"
    JSONL_PATH="$DERIVED_DIR/$SESSION_ID.jsonl"
    if [ -f "$JSONL_PATH" ]; then echo "$JSONL_PATH"; return; fi
  fi
  if [ -n "$SESSION_ID" ]; then
    FOUND=$(find "$PROJECTS_BASE" -name "$SESSION_ID.jsonl" -type f 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then echo "$FOUND"; return; fi
  fi
  LATEST=$(find "$PROJECTS_BASE" -name "*.jsonl" -type f -not -path "*/subagents/*" -newer "$PROJECTS_BASE" 2>/dev/null | xargs ls -t 2>/dev/null | head -1)
  if [ -n "$LATEST" ]; then echo "$LATEST"; fi
}

JSONL=$(find_jsonl)
if [ -n "$JSONL" ]; then
  python3 "$EXPORT_SCRIPT" "$JSONL" --precompact
  hook_log "ok" "precompact snapshot $(basename "$JSONL")"
else
  hook_log "skip" "no jsonl found"
fi

if command -v qmd &>/dev/null; then
  qmd update >/dev/null 2>&1 || true
  qmd embed >/dev/null 2>&1 || true
  hook_log "ok" "qmd indexed"
else
  hook_log "skip" "qmd not found"
fi
