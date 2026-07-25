#!/usr/bin/env bash
# hooks-smoke.sh — the hooks are the highest-blast-radius surface: a PreToolUse or
# UserPromptSubmit hook that crashes or emits non-JSON can BLOCK EVERY action, and a
# safety hook that fails-open leaks secrets / allows `rm -rf`. Nothing tested them.
# This gate: (1) every hook survives a representative event with exit 0 + valid-JSON-or-empty
# stdout; (2) the three SAFETY hooks actually BLOCK bad input and ALLOW benign input.
# Runs in a throwaway HOME so hook side effects (logs, markers) never touch the real machine.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/hooks-smoke.XXXXXX")" && pwd -P)"; export HOME="$SB"  # -P: physical path so realpath-based guards match $HOME (/tmp→/private symlink)
mkdir -p "$SB/.claude" "$SB/vault/logs" "$SB/Documents/vault-work"
FAIL=0
chk(){ if [ "$2" = 0 ]; then printf '  ✓ %s\n' "$1"; else printf '  ✗ %s\n' "$1"; FAIL=1; fi; }

# run <hook-path> <stdin-json> → sets OUT (stdout) and RC (exit code)
run(){ OUT="$(printf '%s' "$2" | bash "$1" 2>/dev/null)"; RC=$?; }
# stdout must be empty OR parseable JSON (a crash prints a traceback / partial text → fails)
json_or_empty(){ local s; s="$(printf '%s' "$1" | tr -d '[:space:]')"; [ -z "$s" ] && return 0; printf '%s' "$1" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null; }

# Representative superset event — benign, so every hook should allow (exit 0).
EVENT='{"session_id":"smoke","source":"startup","cwd":"'"$SB"'/Documents/vault-work","tool_name":"Bash","tool_input":{"command":"echo hi","file_path":"'"$SB"'/notes/x.md"},"tool_response":{},"prompt":"hello world","transcript_path":""}'

# Decision hooks: Claude Code PARSES their stdout (allow/deny / additionalContext) so it must be
# valid-JSON-or-empty. Non-decision hooks (Stop/PreCompact/SessionStart/Subagent/PostToolUse) may
# print progress noise to stdout — for them we only require non-crash.
DECISION_HOOKS=" block-dangerous-hook.sh file-guard-hook.sh worktree-guard-hook.sh skill-log-hook.sh skill-router-hook.sh allow-python-hook.sh "
echo "== every hook survives a representative benign event (non-crash; decision hooks emit valid-JSON-or-empty) =="
for hk in "$REPO"/vault-scripts/*hook*.sh "$REPO"/claude/scripts/warm-start.sh; do
  [ -f "$hk" ] || continue
  case "$hk" in *hooklib.sh) continue;; esac   # shared lib, not an event handler
  name="$(basename "$hk")"
  run "$hk" "$EVENT"
  ok=0
  [ "$RC" = 0 ] || ok=1                                    # benign event → every hook allows (exit 0)
  case "$DECISION_HOOKS" in *" $name "*) json_or_empty "$OUT" || ok=1;; esac
  chk "$name: survives representative event" "$ok"
done

echo "== safety hooks: BLOCK bad input, ALLOW benign =="
run "$REPO/vault-scripts/block-dangerous-hook.sh" '{"tool_input":{"command":"rm -rf /"}}'; [ "$RC" = 2 ]; chk "block-dangerous BLOCKS 'rm -rf /' (exit 2)" $?
run "$REPO/vault-scripts/block-dangerous-hook.sh" '{"tool_input":{"command":"git push --force origin main"}}'; [ "$RC" = 2 ]; chk "block-dangerous BLOCKS force-push" $?
run "$REPO/vault-scripts/block-dangerous-hook.sh" '{"tool_input":{"command":"ls -la"}}'; [ "$RC" = 0 ]; chk "block-dangerous ALLOWS 'ls -la'" $?

run "$REPO/vault-scripts/file-guard-hook.sh" '{"tool_name":"Write","tool_input":{"file_path":"/tmp/p/.env"}}'; printf '%s' "$OUT" | grep -q '"deny"'; chk "file-guard DENIES writing .env" $?
run "$REPO/vault-scripts/file-guard-hook.sh" '{"tool_name":"Write","tool_input":{"file_path":"/tmp/p/id_rsa.key"}}'; printf '%s' "$OUT" | grep -q '"deny"'; chk "file-guard DENIES writing a .key" $?
run "$REPO/vault-scripts/file-guard-hook.sh" '{"tool_name":"Write","tool_input":{"file_path":"/tmp/p/README.md"}}'; ! printf '%s' "$OUT" | grep -q '"deny"'; chk "file-guard ALLOWS writing README.md" $?

WG="$REPO/vault-scripts/worktree-guard-hook.sh"
# The guard is opt-in (WORKTREE_GUARD_REPOS) — enable it for the fixture repo so the deny path fires.
export WORKTREE_GUARD_CODE="$SB/code" WORKTREE_GUARD_REPOS="my-app"
run "$WG" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$SB/code/my-app/x.py\"}}"; printf '%s' "$OUT" | grep -q '"deny"'; chk "worktree-guard DENIES edit in a primary checkout" $?
run "$WG" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$SB/code/.worktrees/my-app__t/x.py\"}}"; ! printf '%s' "$OUT" | grep -q '"deny"'; chk "worktree-guard ALLOWS edit in a worktree" $?
unset WORKTREE_GUARD_CODE WORKTREE_GUARD_REPOS

rm -rf "$SB"
echo
if [ "$FAIL" = 0 ]; then echo "✓ hooks-smoke PASSED"; else echo "✗ hooks-smoke FAILED"; exit 1; fi
