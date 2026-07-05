#!/bin/bash
# Claude Code session-identity marker.
#
# Tracks live/parallel sessions in ~/vault/logs/active-sessions/<sid>.json.
# NOTE: the Stop hook fires after EVERY assistant turn, not at session close —
# there is no reliable "session ended" event. So liveness is a heartbeat:
# `last_active` is bumped each turn, and a session counts as "live" only if its
# heartbeat is recent. Stale markers are pruned.
#
# Usage (wired in settings.json):
#   session-marker-hook.sh start    # SessionStart  — create/refresh marker
#   session-marker-hook.sh touch    # Stop          — bump heartbeat
#   session-marker-hook.sh --list-live   # consumers (start-work/status) render live sessions
#
# Single source of truth for the liveness window so every consumer agrees.
set -uo pipefail

DIR="$HOME/vault/logs/active-sessions"
LIVE_WINDOW_SECS=$((45 * 60))    # marker is "live" if heartbeat within 45 min
PRUNE_AFTER_SECS=$((12 * 3600))  # delete markers stale > 12h
mkdir -p "$DIR"

MODE="${1:-touch}"
NOW=$(date +%s)
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ── --list-live: print live markers as compact lines (for /start-work, /status) ──
if [ "$MODE" = "--list-live" ]; then
  found=0
  for f in "$DIR"/*.json; do
    [ -e "$f" ] || continue
    la=$(python3 -c "import json,sys;print(json.load(open('$f')).get('last_active_ts',0))" 2>/dev/null || echo 0)
    age=$(( NOW - ${la:-0} ))
    if [ "$age" -gt "$PRUNE_AFTER_SECS" ]; then rm -f "$f" 2>/dev/null; continue; fi
    if [ "$age" -le "$LIVE_WINDOW_SECS" ]; then
      found=1
      python3 -c "
import json
d=json.load(open('$f'))
sid=d.get('session_id','?')[:8]
print(f\"- {sid} · {d.get('project','?')} · {d.get('type','?')} · branch={d.get('branch','-')} · {'pushed' if d.get('pushed') else 'unpushed'} · goal={d.get('goal') or '-'}\")
" 2>/dev/null
    fi
  done
  [ "$found" = 0 ] && echo "(no live sessions)"
  exit 0
fi

# Telemetry only for the real hook modes (start/touch), not --list-live above.
[ "$MODE" = "start" ] && HOOK_EVENT=SessionStart || HOOK_EVENT=Stop
HOOK_NAME=session-marker
source "$(dirname "$0")/hooklib.sh" 2>/dev/null \
  || { hook_outcome(){ :;}; hook_ctx(){ :;}; hook_tool(){ :;}; }

# Read hook stdin
INPUT=$(cat 2>/dev/null || echo '{}')
SID=$(echo "$INPUT"  | python3 -c "import sys,json;print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || true)
CWD=$(echo "$INPUT"  | python3 -c "import sys,json;print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || true)
hook_ctx "$SID" "$CWD"
if [ -z "$SID" ]; then hook_outcome "skip" "no session_id"; exit 0; fi
[ -z "$CWD" ] && CWD="$(pwd)"
MARKER="$DIR/$SID.json"

# Derive git/branch/worktree + a project guess
BRANCH="-"; IS_WT="false"; PROJECT=$(basename "$CWD" | tr '[:upper:]' '[:lower:]')
if git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null; then
  BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "detached")
  gd=$(git -C "$CWD" rev-parse --git-dir 2>/dev/null)
  cd_=$(git -C "$CWD" rev-parse --git-common-dir 2>/dev/null)
  [ "$gd" != "$cd_" ] && IS_WT="true"
fi

# Preserve started_at / goal / pushed across touches
STARTED_TS="$NOW"; STARTED_ISO="$NOW_ISO"; GOAL=""; PUSHED="false"
if [ -f "$MARKER" ]; then
  STARTED_TS=$(python3 -c "import json;print(json.load(open('$MARKER')).get('started_ts',$NOW))" 2>/dev/null || echo "$NOW")
  STARTED_ISO=$(python3 -c "import json;print(json.load(open('$MARKER')).get('started_at','$NOW_ISO'))" 2>/dev/null || echo "$NOW_ISO")
  GOAL=$(python3 -c "import json;print(json.load(open('$MARKER')).get('goal','') or '')" 2>/dev/null || true)
  PUSHED=$(python3 -c "import json;print(str(json.load(open('$MARKER')).get('pushed',False)).lower())" 2>/dev/null || echo false)
fi

# vault-push drops this flag file when it persists a session (see vault-push skill)
[ -f "$DIR/$SID.pushed" ] && PUSHED="true"

# Pass everything via env so the Python sees strings (no shell→Python literal mismatch).
SM_SID="$SID" SM_CWD="$CWD" SM_PROJECT="$PROJECT" SM_BRANCH="$BRANCH" \
SM_WT="$IS_WT" SM_GOAL="$GOAL" SM_PUSHED="$PUSHED" SM_STARTED_ISO="$STARTED_ISO" \
SM_STARTED_TS="$STARTED_TS" SM_NOW_ISO="$NOW_ISO" SM_NOW="$NOW" SM_MARKER="$MARKER" \
python3 - <<'PY' 2>/dev/null || true
import json, os
b = lambda v: str(v).lower() == "true"
json.dump({
  "session_id":   os.environ["SM_SID"],
  "cwd":          os.environ["SM_CWD"],
  "project":      os.environ["SM_PROJECT"],
  "type":         "pm",
  "branch":       os.environ["SM_BRANCH"],
  "worktree":     b(os.environ["SM_WT"]),
  "goal":         os.environ.get("SM_GOAL", ""),
  "pushed":       b(os.environ["SM_PUSHED"]),
  "started_at":   os.environ["SM_STARTED_ISO"],
  "started_ts":   int(os.environ["SM_STARTED_TS"]),
  "last_active":  os.environ["SM_NOW_ISO"],
  "last_active_ts": int(os.environ["SM_NOW"]),
}, open(os.environ["SM_MARKER"], "w"), indent=2)
PY

hook_outcome "ok" "mode=$MODE"
exit 0
