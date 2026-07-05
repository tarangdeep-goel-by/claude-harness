#!/bin/bash
# PostToolUse hook (matcher "Skill|Task") — the SINGLE automatic telemetry capture
# for skill + subagent invocations. One JSON line per invocation → ~/vault/logs/workflow.jsonl.
# Read by /infra-health (the review surface), vault-audit, and workflow-gate.
#
# This hook ABSORBS the former skill-log-hook (PreToolUse Skill → workflow.jsonl) and the
# former events.jsonl sink. There is now ONE real-time invocation log (workflow.jsonl);
# /infra-health reviews it (plus hooks.jsonl for hook health, skills.jsonl for offline
# cost/quality from skill_analyzer.py).
#
# Observe-only: always exit 0, never blocks.
set -uo pipefail

WORKFLOW_LOG="$HOME/vault/logs/workflow.jsonl"
mkdir -p "$(dirname "$WORKFLOW_LOG")"

INPUT="$(cat 2>/dev/null || echo '{}')"

WORKFLOW_LOG="$WORKFLOW_LOG" TT_INPUT="$INPUT" python3 - <<'PY' 2>/dev/null || true
import json, os, time, datetime
try:
    d = json.loads(os.environ.get("TT_INPUT", "") or "{}")
except Exception:
    raise SystemExit(0)

tool = d.get("tool_name", "")
ti = d.get("tool_input", {}) or {}
resp = d.get("tool_response", {})
cwd = d.get("cwd", "") or ""

if tool == "Skill":
    kind = "skill"
    name = (ti.get("skill") or ti.get("name") or "").strip()
    args = " ".join(str(ti.get("args") or "").split())[:80]
elif tool == "Task":
    kind = "agent"
    name = (ti.get("subagent_type") or ti.get("description") or "?").strip()
    args = ""
else:
    raise SystemExit(0)

if not name:
    raise SystemExit(0)

# Best-effort outcome from tool_response.
outcome = "ok"
if isinstance(resp, dict) and (resp.get("is_error") or resp.get("error")):
    outcome = "error"

project = os.path.basename(cwd) if cwd else "unknown"

# `skill` field kept for backward-compat (vault-audit + workflow-gate grep it).
rec = {
    "ts": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "ts_epoch": int(time.time()),
    "skill": name,
    "kind": kind,
    "project": project,
    "args": args,
    "outcome": outcome,
    "session": (d.get("session_id") or "")[:8],
    "cwd": cwd,
}
with open(os.environ["WORKFLOW_LOG"], "a") as f:
    f.write(json.dumps(rec) + "\n")
PY
exit 0
