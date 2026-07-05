# hooklib.sh — shared telemetry for Claude Code hooks.  (sourced, not executed)
#
# Gives every hook uniform, low-overhead telemetry with ZERO per-hook bookkeeping:
# it captures a start time on source, installs an EXIT trap, and emits exactly ONE
# standardized JSON line to ~/vault/logs/hooks.jsonl on any exit path — including
# crashes (set -e aborts), early returns, and signals.
#
# Usage — near the top of a hook, BEFORE any work:
#     HOOK_NAME=auto-checkpoint          # required: short hook id
#     HOOK_EVENT=Stop                    # optional: CC event (Stop|PreToolUse|...)
#     source "$(dirname "$0")/hooklib.sh" 2>/dev/null \
#       || { hook_outcome(){ :;}; hook_ctx(){ :;}; hook_tool(){ :;}; }
#     ...
#     hook_ctx "$SID" "$CWD"             # optional: attach session + cwd
#     hook_tool "$TOOL_NAME"             # optional: attach matched tool (Pre/Post)
#     hook_outcome ok "stash created"    # set final outcome + detail (last call wins)
#
# Emitted record fields: ts, ts_epoch, hook, event, outcome, detail,
#   duration_ms, exit_code, session, cwd, tool, host, pid.
# If hook_outcome is never called, outcome is derived from the exit code
# (0->ok, 2->block, *->error) so failures are never invisible.
#
# Design notes:
#  - Pure-bash emit (no python on the hot path) so PreToolUse hooks stay cheap.
#  - Writes ONLY to the log file, never stdout — safe for hooks that print a
#    permission-decision / additionalContext JSON to stdout.
#  - Never aborts its parent: every step is guarded so a sourcing failure or a
#    missing tool degrades to "no telemetry", not "broken hook".

if [ -n "${_HOOKLIB_LOADED:-}" ]; then return 0; fi
_HOOKLIB_LOADED=1

HOOKS_LOG="${HOOKS_LOG:-$HOME/vault/logs/hooks.jsonl}"
mkdir -p "$(dirname "$HOOKS_LOG")" 2>/dev/null || true

# Current wall-clock in integer milliseconds. Prefers GNU `date +%s%N`, falls
# back to perl Time::HiRes (always present on macOS), then whole seconds.
_hook_now_ms() {
  local n
  n=$(date +%s%N 2>/dev/null || true)
  case "$n" in
    ""|*[!0-9]*) ;;                                  # empty or contains literal 'N'
    *) if [ "${#n}" -ge 16 ]; then printf '%s' "$(( n / 1000000 ))"; return 0; fi ;;
  esac
  n=$(perl -MTime::HiRes -e 'printf "%d", Time::HiRes::time()*1000' 2>/dev/null || true)
  if [ -n "$n" ]; then printf '%s' "$n"; return 0; fi
  printf '%s' "$(( $(date +%s) * 1000 ))"
}

# Minimal JSON-string escaper (backslash, doublequote, control chars).
_hook_esc() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  s="${s//$'\t'/ }"
  s="${s//$'\r'/ }"
  printf '%s' "$s"
}

# Rotate the log if it grows past ~8MB so hot-path hooks can't bloat it.
_hook_rotate() {
  local max=$((8 * 1024 * 1024)) sz
  sz=$(wc -c <"$HOOKS_LOG" 2>/dev/null || echo 0)
  if [ "${sz:-0}" -gt "$max" ]; then
    mv -f "$HOOKS_LOG.1" "$HOOKS_LOG.2" 2>/dev/null || true
    mv -f "$HOOKS_LOG" "$HOOKS_LOG.1" 2>/dev/null || true
  fi
}
_hook_rotate

_HOOK_START_MS="$(_hook_now_ms)"
_HOOK_NAME="${HOOK_NAME:-unknown}"
_HOOK_EVENT="${HOOK_EVENT:-}"
_HOOK_OUTCOME=""
_HOOK_DETAIL=""
_HOOK_SESSION=""
_HOOK_CWD=""
_HOOK_TOOL=""
_HOOK_EMITTED=""
_HOOK_HOST="$(hostname -s 2>/dev/null || echo '')"

hook_outcome() { _HOOK_OUTCOME="${1:-}"; _HOOK_DETAIL="${2:-}"; }
hook_ctx()     { _HOOK_SESSION="${1:-}"; _HOOK_CWD="${2:-}"; }
hook_tool()    { _HOOK_TOOL="${1:-}"; }

_hook_emit() {
  local ec=$?
  if [ -n "$_HOOK_EMITTED" ]; then return 0; fi
  _HOOK_EMITTED=1

  local outcome="$_HOOK_OUTCOME"
  if [ -z "$outcome" ]; then
    case "$ec" in 0) outcome=ok ;; 2) outcome=block ;; *) outcome=error ;; esac
  fi

  local now dur
  now="$(_hook_now_ms)"
  dur=$(( now - _HOOK_START_MS ))
  [ "$dur" -lt 0 ] && dur=0

  local line
  line="{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"ts_epoch\":$(date +%s)"
  line="$line,\"hook\":\"$(_hook_esc "$_HOOK_NAME")\""
  [ -n "$_HOOK_EVENT" ]   && line="$line,\"event\":\"$(_hook_esc "$_HOOK_EVENT")\""
  line="$line,\"outcome\":\"$(_hook_esc "$outcome")\""
  line="$line,\"detail\":\"$(_hook_esc "$_HOOK_DETAIL")\""
  line="$line,\"duration_ms\":$dur,\"exit_code\":$ec"
  [ -n "$_HOOK_SESSION" ] && line="$line,\"session\":\"$(_hook_esc "${_HOOK_SESSION:0:8}")\""
  [ -n "$_HOOK_CWD" ]     && line="$line,\"cwd\":\"$(_hook_esc "$_HOOK_CWD")\""
  [ -n "$_HOOK_TOOL" ]    && line="$line,\"tool\":\"$(_hook_esc "$_HOOK_TOOL")\""
  [ -n "$_HOOK_HOST" ]    && line="$line,\"host\":\"$(_hook_esc "$_HOOK_HOST")\""
  line="$line,\"pid\":$$}"

  printf '%s\n' "$line" >> "$HOOKS_LOG" 2>/dev/null || true
}

trap _hook_emit EXIT
