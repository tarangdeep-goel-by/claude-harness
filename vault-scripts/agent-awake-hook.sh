#!/bin/bash
# agent-awake-hook.sh — keep this Mac awake (incl. LID-CLOSED on BATTERY) only
# while a Claude agent is actively working, then allow it to sleep.
#
# WHY pmset (not caffeinate): `pmset disablesleep` is the ONLY macOS knob that
# survives clamshell-sleep on battery. caffeinate's -i ignores lid-close and -s
# holds only on AC — so Claude Code's built-in wake-lock can't cover this case.
#
# We hold the block from turn-start → turn-done via hooks, reference-counted
# across parallel sessions by per-session marker files under $DIR:
#   UserPromptSubmit → mark      : this session is working   → enable block
#   Stop             → sweep     : this session's turn done  → prune dead, release if none left
#   SessionStart     → reconcile : self-heal — prune dead markers, release if none active
#
# CRASH-SAFE / NO FALSE-IDLE: a marker is pruned only when its session's CLI
# process (matched by --session-id <uuid>) is GONE. A long-running turn is never
# cut off; a crashed session can't wedge sleep off forever.
#
# FAIL-SAFE: every path is a silent no-op — this hook must NEVER block a prompt
# or error a turn, and must print nothing to stdout (UserPromptSubmit stdout is
# injected into model context). Needs one-time passwordless sudo for
# /usr/bin/pmset; without it, it degrades to a harmless no-op.
set -uo pipefail

DIR="$HOME/vault/logs/agent-awake"
mkdir -p "$DIR" 2>/dev/null || true
PMSET=/usr/bin/pmset

INPUT=$(cat 2>/dev/null || true)
SID=$(printf '%s' "$INPUT" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('session_id','') or 'unknown')" 2>/dev/null \
  || echo unknown)

# disablesleep (SleepDisabled) is a single GLOBAL flag → set it with -a.
# Blocks system sleep (lid-close incl. clamshell-on-battery, and idle) while an
# agent works; released between turns. -b kept as a fallback only.
enable_block()  { sudo -n "$PMSET" -a disablesleep 1 2>/dev/null || sudo -n "$PMSET" -b disablesleep 1 2>/dev/null || true; }
release_block() { sudo -n "$PMSET" -a disablesleep 0 2>/dev/null || sudo -n "$PMSET" -b disablesleep 0 2>/dev/null || true; }

prune_dead() {
  local f s
  for f in "$DIR"/*; do
    [ -e "$f" ] || continue
    s=$(basename "$f")
    [ "$s" = unknown ] && continue           # can't map to a pid; cleared by its own sweep
    pgrep -f "$s" >/dev/null 2>&1 || rm -f "$f" 2>/dev/null || true
  done
}

any_active() { [ -n "$(ls -A "$DIR" 2>/dev/null)" ]; }

case "${1:-}" in
  mark)
    touch "$DIR/$SID" 2>/dev/null || true
    enable_block
    ;;
  sweep)
    rm -f "$DIR/$SID" 2>/dev/null || true
    prune_dead
    any_active || release_block
    ;;
  reconcile)
    prune_dead
    any_active || release_block
    ;;
esac
exit 0
