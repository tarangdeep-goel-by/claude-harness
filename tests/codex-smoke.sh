#!/usr/bin/env bash
# codex-smoke.sh - read-only checks for the Codex hook port.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d "${TMPDIR:-/tmp}/codex-smoke.XXXXXX")"
FAIL=0

cleanup() { rm -rf "$SB"; }
trap cleanup EXIT

chk() {
  if [ "$2" = 0 ]; then
    printf '  OK %s\n' "$1"
  else
    printf '  FAIL %s\n' "$1"
    FAIL=1
  fi
}

json_or_empty() {
  local s
  s="$(printf '%s' "$1" | tr -d '[:space:]')"
  [ -z "$s" ] && return 0
  printf '%s' "$1" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1
}

adapter_allows() {
  local out rc
  out="$(printf '%s' "$1" | python3 "$REPO/codex/scripts/codex_hook_adapter.py" PermissionRequest 2>/dev/null)"
  rc=$?
  [ "$rc" = 0 ] || return 1
  json_or_empty "$out" || return 1
  ! printf '%s' "$out" | grep -Eiq 'deny|block'
}

adapter_blocks() {
  local out rc
  out="$(printf '%s' "$1" | python3 "$REPO/codex/scripts/codex_hook_adapter.py" PreToolUse 2>/dev/null)"
  rc=$?
  [ "$rc" = 2 ] && return 0
  printf '%s' "$out" | grep -Eiq 'deny|block'
}

echo "== required Codex sources =="
required=(
  "catalog-codex-sessions.sh"
  "codex/hooks.json"
  "codex/config.example.toml"
  "codex/scripts/codex_hook_adapter.py"
  "codex/scripts/codex_stop_worker.sh"
  "codex/scripts/codex_warm_start.sh"
  "codex/scripts/export_codex_session.py"
  "codex/scripts/finalize_session.sh"
  "codex/scripts/codex_qmd_refresh.sh"
  "codex/scripts/bootstrap_prompt.py"
  "codex/scripts/backfill_codex_sessions.py"
  "codex/scripts/codex_hooks_doctor.py"
  "read-codex-session.sh"
)
for rel in "${required[@]}"; do
  [ -f "$REPO/$rel" ]
  chk "$rel exists" $?
done

echo "== static checks =="
python3 -m json.tool "$REPO/codex/hooks.json" >/dev/null 2>&1
chk "codex/hooks.json parses as JSON" $?

python3 - "$REPO/codex/hooks.json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
commands = []
for entries in data.get("hooks", {}).values():
    for entry in entries:
        for hook in entry.get("hooks", []):
            command = hook.get("command", "")
            if command:
                commands.append(command)
assert commands and all("~/.codex/scripts/codex_hook_adapter.py" in command for command in commands)
PY
chk "source hooks use Codex-native script path template" $?
python3 - "$REPO/codex/hooks.json" <<'PY'
import json, sys
required = {"SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","PermissionRequest","Stop","PreCompact","SubagentStart"}
events = set(json.load(open(sys.argv[1])).get("hooks", {}))
assert required <= events, sorted(required - events)
PY
chk "required Codex hook events are present" $?

py_files=()
while IFS= read -r -d '' f; do py_files+=("$f"); done < <(find "$REPO/codex/scripts" -maxdepth 1 -type f -name '*.py' -print0 2>/dev/null)
if [ "${#py_files[@]}" -gt 0 ]; then
  PYTHONDONTWRITEBYTECODE=1 PYTHONPYCACHEPREFIX="$SB/pycache" python3 -m py_compile "${py_files[@]}"
  chk "Python scripts compile" $?
else
  chk "Python scripts compile" 1
fi

sh_files=()
while IFS= read -r -d '' f; do sh_files+=("$f"); done < <(find "$REPO/codex/scripts" -maxdepth 1 -type f -name '*.sh' -print0 2>/dev/null)
if [ "${#sh_files[@]}" -gt 0 ]; then
  sh_ok=0
  for f in "${sh_files[@]}"; do
    bash -n "$f" || sh_ok=1
  done
  chk "shell scripts pass bash -n" "$sh_ok"
else
  chk "shell scripts pass bash -n" 1
fi

top_sh_ok=0
for f in "$REPO/install-codex.sh" "$REPO/catalog-codex-sessions.sh" "$REPO/read-codex-session.sh"; do
  bash -n "$f" || top_sh_ok=1
done
chk "top-level Codex shell scripts pass bash -n" "$top_sh_ok"

install_home="$SB/home"
mkdir -p "$install_home"
HOME="$install_home" "$REPO/install-codex.sh" >/dev/null 2>&1
chk "install-codex.sh runs in throwaway HOME" $?
python3 -m json.tool "$install_home/.codex/hooks.json" >/dev/null 2>&1
chk "installed hooks.json parses as JSON" $?
! grep -q '~/.codex' "$install_home/.codex/hooks.json" 2>/dev/null
chk "installed hooks expand Codex script paths" $?
grep -q "$install_home/.codex/scripts/codex_hook_adapter.py" "$install_home/.codex/hooks.json" 2>/dev/null
chk "installed hooks point at Codex-native runtime" $?
grep -q "CODEX_HARNESS_MEMORY_SYNC" "$REPO/codex/scripts/codex_stop_worker.sh" "$REPO/codex/scripts/finalize_session.sh" 2>/dev/null
chk "semantic memory sync is opt-in" $?

fixture_dir="$install_home/.codex/sessions/2026/07/27"
mkdir -p "$fixture_dir"
fixture_path="$fixture_dir/rollout-2026-07-27T00-00-00-fileprefix-does-not-match.jsonl"
fixture_id="019fixture-codex-smoke"
python3 - "$fixture_path" "$REPO" "$fixture_id" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
repo = sys.argv[2]
session_id = sys.argv[3]
rows = [
    {"timestamp": "2026-07-27T00:00:00Z", "type": "session_meta", "payload": {"id": session_id, "cwd": repo, "model": "gpt-smoke", "cli_version": "0.0.0"}},
    {"timestamp": "2026-07-27T00:00:01Z", "type": "response_item", "payload": {"type": "message", "role": "developer", "content": [{"type": "input_text", "text": "<permissions instructions>runtime-only</permissions instructions>"}]}},
    {"timestamp": "2026-07-27T00:00:02Z", "type": "response_item", "payload": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "<recommended_plugins>\nplugin metadata\n</recommended_plugins>\n# AGENTS.md instructions\nruntime-only"}]}},
    {"timestamp": "2026-07-27T00:00:03Z", "type": "response_item", "payload": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "<environment_context>\n  <cwd>/tmp</cwd>\n</environment_context>"}]}},
    {"timestamp": "2026-07-27T00:00:04Z", "type": "response_item", "payload": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "Port the harness to Codex."}]}},
    {"timestamp": "2026-07-27T00:00:05Z", "type": "response_item", "payload": {"type": "function_call", "name": "exec_command", "arguments": "{\"workdir\":\"" + repo + "\"}"}},
    {"timestamp": "2026-07-27T00:00:06Z", "type": "response_item", "payload": {"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "[external_agent_tool_call: Bash]\ncommand: echo noisy\n[/external_agent_tool_call]"}]}},
    {"timestamp": "2026-07-27T00:00:07Z", "type": "response_item", "payload": {"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "Codex port fixture response."}]}},
]
path.write_text("\n".join(json.dumps(row) for row in rows) + "\n")
PY
chk "Codex fixture session written" $?
HOME="$install_home" "$REPO/catalog-codex-sessions.sh" 30 "$SB/codex-session-catalog.md" >/dev/null 2>&1
chk "catalog-codex-sessions.sh catalogs fixture" $?
grep -q "Port the harness to Codex" "$SB/codex-session-catalog.md" 2>/dev/null
chk "Codex catalog includes opening goal" $?
! grep -Eq "recommended_plugins|AGENTS.md instructions|environment_context" "$SB/codex-session-catalog.md" 2>/dev/null
chk "Codex catalog excludes injected context" $?
read_out="$(HOME="$install_home" "$REPO/read-codex-session.sh" 019fixture 400 2>/dev/null)"
printf '%s' "$read_out" | grep -q "USER: Port the harness to Codex"
chk "read-codex-session.sh resolves session_meta id prefix and prints user text" $?
printf '%s' "$read_out" | grep -q "ASSISTANT: Codex port fixture response"
chk "read-codex-session.sh prints fixture assistant text" $?
! printf '%s' "$read_out" | grep -Eq "recommended_plugins|AGENTS.md instructions|environment_context|external_agent_tool_call"
chk "read-codex-session.sh excludes injected/tool context" $?

HOME="$install_home" "$install_home/.codex/scripts/export_codex_session.py" "$fixture_path" >/dev/null 2>&1
chk "export_codex_session.py exports fixture with default vault target" $?
exported="$(find "$install_home/vault/sessions" -type f -name '*.md' -print 2>/dev/null | head -1)"
[ -n "$exported" ] && grep -q "source: codex" "$exported" 2>/dev/null
chk "exported fixture has Codex source frontmatter" $?
grep -q "Port the harness to Codex" "$exported" 2>/dev/null
chk "exported fixture includes transcript text" $?
! grep -Eq "recommended_plugins|AGENTS.md instructions|environment_context|external_agent_tool_call" "$exported" 2>/dev/null
chk "exported fixture excludes injected/tool context" $?

precompact_payload='{"session_id":"'"$fixture_id"'","session_path":"'"$fixture_path"'","cwd":"'"$REPO"'"}'
printf '%s' "$precompact_payload" | HOME="$install_home" "$install_home/.codex/scripts/codex_hook_adapter.py" PreCompact >/dev/null 2>&1
chk "PreCompact adapter exits cleanly" $?
snapshot="$(find "$install_home/vault/sessions" -type f -name '*_precompact_019fixtu_*.md' -print 2>/dev/null | head -1)"
[ -n "$snapshot" ] && grep -q "type: precompact-state" "$snapshot" 2>/dev/null
chk "PreCompact writes deterministic state snapshot" $?
grep -q "Port the harness to Codex" "$snapshot" 2>/dev/null
chk "PreCompact snapshot includes active user prompt" $?
grep -q "Full transcript:" "$snapshot" 2>/dev/null
chk "PreCompact snapshot links transcript export" $?

! grep -Eq 'GEMINI_API_KEY[[:space:]]*=[[:space:]]*"AIza' "$REPO/codex/config.example.toml" 2>/dev/null
chk "config example contains no obvious Gemini API key literal" $?

echo "== adapter behavior =="
safe_event='{"tool_name":"Bash","tool":"shell","command":"python3 -c '\''print(42)'\''","tool_input":{"command":"python3 -c '\''print(42)'\''"},"cwd":"'"$REPO"'","session_id":"codex-smoke"}'
adapter_allows "$safe_event"
chk "PermissionRequest allows a safe Python command" $?

reset_event='{"tool_name":"Bash","tool":"shell","command":"git reset --hard","tool_input":{"command":"git reset --hard"},"cwd":"'"$REPO"'","session_id":"codex-smoke"}'
adapter_blocks "$reset_event"
chk "PreToolUse blocks git reset --hard" $?

echo
if [ "$FAIL" = 0 ]; then
  echo "codex-smoke PASSED"
else
  echo "codex-smoke FAILED"
  exit 1
fi
