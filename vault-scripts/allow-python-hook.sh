#!/bin/bash
# Auto-allow safe Bash commands (python, qmd, curl to known APIs).
set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('command', ''))
" 2>/dev/null || true)

# Allow python3/python one-liners and script runs
if [[ "$CMD" =~ ^python3?\  ]] || [[ "$CMD" =~ \|\ *python3?\  ]]; then
  echo '{"decision":"allow"}'
  exit 0
fi

# Allow qmd CLI (vault search/index)
if [[ "$CMD" =~ ^qmd\  ]]; then
  echo '{"decision":"allow"}'
  exit 0
fi

# Allow curl to Metabase and Mixpanel (data analysis APIs)
if [[ "$CMD" =~ curl.*metabase\.stablemoney\.in ]] || [[ "$CMD" =~ curl.*mixpanel\.com ]]; then
  echo '{"decision":"allow"}'
  exit 0
fi
