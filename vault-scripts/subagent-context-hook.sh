#!/bin/bash
# Claude Code SubagentStart hook: inject project conventions + data tool context into every subagent.
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

# Data tool context for vault-work project
if [[ "${CWD:-}" == *"vault-work"* ]]; then
  CONTEXT+="

## Data Analysis Context (auto-injected for vault-work)

**MANDATORY:** Before writing ANY Mixpanel query, Metabase query, or analysis script, you MUST first read the relevant SKILL.md file. The skills contain the canonical gotchas, event naming rules, table routing, and common-mistakes checklists. Skipping them causes silent wrong results.

- Mixpanel work → \`Read('.claude/skills/mixpanel-analytics/SKILL.md')\`
- Metabase work → \`Read('.claude/skills/metabase-query/SKILL.md')\`

The SKILL.md files link to deeper reference files (\`references/*\`) — follow those links when the skill points to them.

**Env vars pre-loaded:** \`MB_API_KEY\`, \`MP_SESSIONID\`, \`MP_CSRFTOKEN\`.

**Scripts:** reuse patterns from \`Notes/<project>/scripts/\`. Save new scripts there — never throwaway inline code. Every script must include a sanity-check block (row counts, null checks, totals, date range)."
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
