#!/bin/bash
# PostToolUse hook — central telemetry for skill + subagent invocations.
# Wired to matcher "Skill|Task" so EVERY skill/subagent use is captured here,
# without each SKILL.md having to self-log. One JSON line per invocation →
# ~/vault/logs/events.jsonl. Read by the infra-health reporter.
set -uo pipefail

HOOK_NAME=tool-telemetry
HOOK_EVENT=PostToolUse
source "$(dirname "$0")/hooklib.sh" 2>/dev/null \
  || { hook_outcome(){ :;}; hook_ctx(){ :;}; hook_tool(){ :;}; }

EVENTS="$HOME/vault/logs/events.jsonl"
mkdir -p "$(dirname "$EVENTS")"

# Light rotation: keep events.jsonl bounded.
if [ -f "$EVENTS" ] && [ "$(wc -c <"$EVENTS" 2>/dev/null || echo 0)" -gt 5242880 ]; then
  mv "$EVENTS" "$EVENTS.1" 2>/dev/null || true
fi

INPUT=$(cat 2>/dev/null || echo '{}')

EVENTS="$EVENTS" TT_INPUT="$INPUT" python3 - <<'PY' 2>/dev/null || true
import json, os, time
try:
    d = json.loads(os.environ.get("TT_INPUT", "") or "{}")
except Exception:
    raise SystemExit(0)
tool = d.get("tool_name", "")
ti   = d.get("tool_input", {}) or {}
resp = d.get("tool_response", {})

if tool == "Skill":
    kind, name = "skill", ti.get("skill") or ti.get("name") or "?"
elif tool == "Task":
    kind, name = "agent", ti.get("subagent_type") or ti.get("description") or "?"
else:
    raise SystemExit(0)

# Best-effort outcome from tool_response (skills/agents usually succeed if no error field)
outcome = "ok"
if isinstance(resp, dict) and (resp.get("is_error") or resp.get("error")):
    outcome = "error"

rec = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "ts_epoch": int(time.time()),
    "kind": kind,
    "name": name,
    "session": (d.get("session_id") or "")[:8],
    "cwd": d.get("cwd", ""),
    "outcome": outcome,
}
with open(os.environ["EVENTS"], "a") as f:
    f.write(json.dumps(rec) + "\n")
PY
hook_tool "$(echo "$INPUT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || true)"
hook_outcome "ok" "event recorded"
exit 0
