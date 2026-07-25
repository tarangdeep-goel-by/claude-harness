#!/bin/bash
# workflow-gate-hook.sh — PreToolUse gate for the GLM orchestrator.
#
# Blocks code MUTATIONS (Edit/Write/MultiEdit/NotebookEdit) unless the
# workflow-engine skill (or task-triage) has been logged TODAY (UTC) in the
# workflow audit log. Enforces "triage before you touch project code" — the
# single highest-value countermeasure for GLM's known skill-under-triggering.
#
# Design notes:
#   - Date-based (UTC day), not session-scoped. Subagent-safe: the orchestrator
#     logs workflow-engine BEFORE dispatching any subagent, so by the time a
#     subagent mutates a file the day's entry already exists. Acceptable hole:
#     a second task later the same day passes the gate without re-triaging.
#   - Harness/vault/config paths are allowlisted (not project code) and to
#     prevent self-deadlock on the audit log itself.
#   - Payload + output convention match file-guard-hook.sh (jq on stdin;
#     deny = print {"decision":"deny","reason":...} + exit 0; allow = silent).
set -uo pipefail

LOG="${WORKFLOW_GATE_LOG:-$HOME/vault/logs/workflow.jsonl}"
TODAY="$(date -u +%Y-%m-%d)"

INPUT="$(cat)"
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')"
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // ""')"

# Only mutations are gated (never Read/grep/etc.).
case "$TOOL_NAME" in
  Edit|Write|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

# Allowlist: harness / router / vault / config are meta, not project code.
case "$FILE_PATH" in
  "$HOME/.claude/"*|"$HOME/.claude-code-router/"*|"$HOME/vault/"*|"$HOME/.config/"*|"")
    exit 0 ;;
esac

# Gate: was workflow-engine or task-triage logged today (UTC)?
if [[ -f "$LOG" ]] && grep -qE "\"ts\":\"${TODAY}.*\"skill\":\"(workflow-engine|task-triage)\"" "$LOG"; then
  exit 0   # triaged — allow
fi

# Not triaged — block.
jq -n --arg reason "🚦 Workflow Gate: code edit blocked. Invoke the workflow-engine skill first (it logs to $LOG). No triage entry for $TODAY. Path: $FILE_PATH" \
  '{"decision": "deny", "reason": $reason}'
