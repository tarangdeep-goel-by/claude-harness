#!/bin/bash
# Claude Code Stop hook: export current session transcript.
# MERGED (old keeper + temp telemetry):
#   - BASE = old's evolved version (learning-detector DISABLED + qmd-in-Stop
#     REMOVED — both deliberate perf/relevance decisions, kept as-is).
#   - ADDED from temp = hooklib.sh telemetry sourcing (richer hooks.jsonl that
#     infra-health reads) + the skill_analyzer.py call (produces skills.jsonl /
#     routing.jsonl in the session-export pipeline, which infra-health requires).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPORT_SCRIPT="$SCRIPT_DIR/export-session.py"
PROJECTS_BASE="$HOME/.claude/projects"
START_TS=$(date +%s)
# Debounce file set per-session after SESSION_ID is read
DEBOUNCE_SECS=300  # 5 minutes

HOOK_NAME=session-export
HOOK_EVENT=Stop
source "$SCRIPT_DIR/hooklib.sh" 2>/dev/null \
  || { hook_outcome(){ :;}; hook_ctx(){ :;}; hook_tool(){ :;}; }

# Read hook input from stdin
INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null || true)
SESSION_CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null || true)
hook_ctx "$SESSION_ID" "$SESSION_CWD"
# hook_log: legacy shim → accumulate detail, defer to single trap emit.
hook_log() { hook_outcome "$1" "$(printf '%s%s%s' "${_HOOK_DETAIL:-}" "${_HOOK_DETAIL:+; }" "${2:-}")"; }

# Per-session debounce: skip if this session exported < 5 minutes ago
DEBOUNCE_FILE="/tmp/claude-session-export-${SESSION_ID:-unknown}"
if [ -f "$DEBOUNCE_FILE" ]; then
  LAST_RUN=$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo 0)
  ELAPSED=$(( START_TS - LAST_RUN ))
  if [ "$ELAPSED" -lt "$DEBOUNCE_SECS" ]; then
    hook_outcome "skip" "debounced (${ELAPSED}s < ${DEBOUNCE_SECS}s)"
    exit 0
  fi
fi

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
  python3 "$EXPORT_SCRIPT" "$JSONL"

  # learning-detector DISABLED 2026-06-16 (old keeper decision) — its queue
  # (~/vault/learnings-queue.jsonl) was never consumed (reflect skill: 0 uses in
  # 129 sessions) and had started capturing assistant prose as "learnings".
  # Re-enable only alongside a regular /reflect review habit.
  # LEARNING_SCRIPT="$SCRIPT_DIR/learning-detector.py"
  # [ -f "$LEARNING_SCRIPT" ] && python3 "$LEARNING_SCRIPT" "$JSONL" &

  # skill_analyzer (ADDED from temp): produces skills.jsonl + routing.jsonl that
  # the infra-health skill reads. Backgrounded so it never adds to Stop latency;
  # no-op if the script is absent.
  SKILL_ANALYZER="$SCRIPT_DIR/skill_analyzer.py"
  [ -f "$SKILL_ANALYZER" ] && python3 "$SKILL_ANALYZER" "$JSONL" &

  hook_log "ok" "exported $(basename "$JSONL")"
else
  hook_log "skip" "no jsonl found"
fi

echo "$START_TS" > "$DEBOUNCE_FILE"

# qmd update/embed intentionally NOT run here (old keeper decision) —
# warm-start.sh (SessionStart) handles indexing in a backgrounded flush.
# Running it in the Stop hook added ~47s to every turn.
