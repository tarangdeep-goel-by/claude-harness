#!/usr/bin/env bash
# read-chat.sh — print ONE claude.ai/desktop conversation (your messages + Claude's replies) from a
# data export, so you can deep-read the high-signal chats the catalog points to. READ-ONLY.
#   Usage:  ./read-chat.sh <path/to/conversations.json> <uuid-prefix | name-substring> [maxchars]
set -uo pipefail
SRC="${1:?conversations.json}"; SEL="${2:?conversation uuid-prefix or name substring}"; CAP="${3:-1500}"
[ -f "$SRC" ] || { echo "not found: $SRC"; exit 1; }
command -v jq >/dev/null || { echo "jq required"; exit 1; }
jq -r --arg sel "$SEL" --argjson cap "$CAP" '
  (if type=="array" then . else (.conversations? // []) end)
  | map(select( ((.uuid // "") | startswith($sel)) or ((.name // "") | ascii_downcase | contains($sel|ascii_downcase)) ))
  | (.[0] // empty)
  | ( "# " + (.name // "untitled") + "  ·  " + ((.updated_at // .created_at // "")[0:10]) + "\n" ),
    ( .chat_messages[]?
      | ( (.text // ([ .content[]? | select(.type=="text") | .text ] | join(" "))) ) as $t
      | if (($t // "")|length) > 0
        then (if .sender=="human" then "🧑 YOU: " else "🤖 CLAUDE: " end) + ($t[0:$cap])
        else empty end )
' "$SRC" 2>/dev/null
