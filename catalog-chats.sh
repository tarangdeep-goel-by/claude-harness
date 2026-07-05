#!/usr/bin/env bash
# catalog-chats.sh — map your Claude desktop-app / claude.ai chat history into the SAME catalog
# format as catalog-sessions.sh, so the ADOPT_FROM_HISTORY synthesis can mine it too.
#
# Desktop/web/cowork chats live server-side (no local cache, unlike Claude Code). The local artifact
# is the official DATA EXPORT: claude.ai → Settings → Privacy → "Export data" → you get an email with
# a zip → unzip → conversations.json (your chats) [+ projects.json]. Point this at conversations.json.
# READ-ONLY.
#   Usage:  ./catalog-chats.sh <path/to/conversations.json> [DAYS] [OUT_FILE]   (default 30 → ./chat-catalog.md)
set -uo pipefail
SRC="${1:?path to conversations.json (from your claude.ai data export)}"
DAYS="${2:-30}"; OUT="${3:-./chat-catalog.md}"
[ -f "$SRC" ] || { echo "not found: $SRC — request it via claude.ai → Settings → Privacy → Export data"; exit 1; }
command -v jq >/dev/null || { echo "jq required"; exit 1; }
CUT=$(( $(date +%s) - DAYS*86400 ))
{
  echo "# Claude chat catalog — last $DAYS days (desktop app / claude.ai / cowork)"
  echo "_source: $SRC · generated $(date +%Y-%m-%d) · read-only_"
  echo
  echo "Your claude.ai conversations, newest first, with the opening message. Cluster these into"
  echo "projects alongside your Claude Code sessions, then deep-read the rich ones (read-chat.sh)."
  echo
  jq -r --argjson cut "$CUT" '
    (if type=="array" then . else (.conversations? // []) end)
    | map(select(((.updated_at // .created_at // "") | (fromdateiso8601? // 0)) >= $cut))
    | sort_by(.updated_at // .created_at // "") | reverse
    | .[]
    | . as $c
    | (($c.chat_messages // []) | map(select(.sender=="human")) ) as $h
    | (($h[0].text // ($h[0].content[]?.text?)) // "") as $first
    | "- **" + (($c.updated_at // $c.created_at // "??????????")[0:10]) + "** `"
      + (($c.uuid // "")[0:8]) + "` — " + (($c.name // "untitled") | gsub("\n";" "))
      + " _(msgs: " + (($c.chat_messages // [] | length)|tostring) + ")_"
      + (if ($first|length)>0 then "\n  - opening: " + ($first | gsub("\n";" ") | .[0:200]) else "" end)
  ' "$SRC" 2>/dev/null
  echo; echo "---"
  echo "_Next: ADOPT_FROM_HISTORY.md → cluster (with your Claude Code sessions) → deep-read → build the vault._"
} > "$OUT"
n=$(grep -c '^- ' "$OUT" 2>/dev/null); n=${n:-0}   # grep -c prints 0 but exits 1 on no match
if [ "$n" -eq 0 ]; then
  echo "⚠ 0 conversations in the last $DAYS days."
  echo "  Data exports lag (hours–days to arrive), so a '30' window can miss everything. Widen it:"
  echo "    ./catalog-chats.sh \"$SRC\" 365"
  echo "  (and confirm $SRC is the conversations.json from your claude.ai export, not empty.)"
else
  echo "✓ wrote $OUT — $n conversations in the last $DAYS days"
fi
