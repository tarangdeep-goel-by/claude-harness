#!/bin/bash
# Claude Code SubagentStart hook: inject project conventions into every subagent.
set -euo pipefail

INPUT=$(cat)

CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || true)

# Build context string
CONTEXT="## Subagent Guidelines (auto-injected)
- Verify before claiming done — run the proof command, read the output
- Follow existing code patterns — read surrounding code before writing
- Keep changes minimal and surgical — no premature abstractions
- Never commit to main/master — use feature branches
- If a task involves tests: write the failing test first, then implement"

# Add project-specific rules if CLAUDE.md exists in project dir
if [ -n "$CWD" ] && [ -f "$CWD/CLAUDE.md" ]; then
  PROJECT_HINTS=$(grep -E '^\*\*|^- \*\*' "$CWD/CLAUDE.md" 2>/dev/null | head -8 | sed 's/^/  /')
  if [ -n "$PROJECT_HINTS" ]; then
    CONTEXT+="
## Project Rules (from CLAUDE.md)
$PROJECT_HINTS"
  fi
fi

# Output as hook JSON
python3 -c "
import json, sys
ctx = sys.stdin.read()
print(json.dumps({
  'hookSpecificOutput': {
    'hookEventName': 'SubagentStart',
    'additionalContext': ctx
  }
}))" <<< "$CONTEXT"
