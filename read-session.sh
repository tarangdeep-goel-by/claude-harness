#!/usr/bin/env bash
# read-session.sh — print ONE session's real conversation (the human's typed prompts + Claude's
# prose replies), stripping tool calls, tool results, and injected hook context. Lets a returning
# user's Claude deep-read the high-signal sessions the catalog points to, without drowning in noise.
# READ-ONLY.
#   Usage:  ./read-session.sh <session-id | /path/to.jsonl> [maxchars-per-message]
set -uo pipefail
arg="${1:?session id (8+ chars) or path to a .jsonl}"; CAP="${2:-1500}"
f="$arg"
[ -f "$f" ] || f="$(find "$HOME/.claude/projects" -name "${arg}*.jsonl" 2>/dev/null | head -1)"
[ -f "$f" ] || { echo "session not found: $arg"; exit 1; }
command -v jq >/dev/null || { echo "jq required"; exit 1; }

echo "# session $(basename "$f" .jsonl)  ·  $(date -r "$f" +%Y-%m-%d)"
grep '"type":"ai-title"' "$f" 2>/dev/null | tail -1 | jq -r '"## " + (.aiTitle // "untitled")' 2>/dev/null
echo
# USER: only string content (what was actually typed). ASSISTANT: join the text blocks, drop tool_use.
jq -r --argjson cap "$CAP" '
  if .type=="user" and (.content|type)=="string" then
    "🧑 USER: " + (.content[0:$cap])
  elif .type=="assistant" then
    (( .message.content? // .content? // [] ) ) as $c
    | ( if ($c|type)=="array" then ([ $c[] | select(.type=="text") | .text ] | join(" "))
        elif ($c|type)=="string" then $c else "" end ) as $t
    | if ($t|length) > 0 then "🤖 CLAUDE: " + ($t[0:$cap]) else empty end
  else empty end' "$f" 2>/dev/null
