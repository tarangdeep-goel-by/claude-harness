#!/bin/bash
# PreToolUse hook on the Skill tool: log every skill invocation to workflow.jsonl.
# This is the central skill-telemetry capture — no per-skill code needed. Any
# skill Claude invokes via the Skill tool is recorded here automatically.
#
# IMPORTANT: this hook is observe-only. It MUST always allow the skill to run
# (exit 0, no decision JSON on stdout). It never blocks.
#
# Caveats:
#  - Captures Skill-TOOL invocations only. User-typed /slash-commands that the
#    harness injects as prompts do NOT pass through here (add a UserPromptSubmit
#    hook for those).
#  - vault-push also self-logs in its skill body, so it may appear twice; the
#    audit should de-dupe by (ts, skill) within a few seconds if that matters.
set -euo pipefail

WORKFLOW_LOG="$HOME/vault/logs/workflow.jsonl"
mkdir -p "$(dirname "$WORKFLOW_LOG")"

INPUT=$(cat)

# Extract skill name, cwd, and a short args preview from the PreToolUse payload.
read -r SKILL CWD ARGS <<EOF
$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = d.get('tool_input', {}) or {}
skill = (ti.get('skill') or ti.get('name') or '').strip()
cwd = (d.get('cwd') or '').strip()
args = (ti.get('args') or '')
# single-line, length-capped, no quotes/whitespace that would break the TSV read
args = ' '.join(str(args).split())[:80].replace('\"', \"'\")
# guard against empty fields collapsing the positional read
print(skill or '-', cwd or '-', args or '-')
" 2>/dev/null || true)
EOF

# Nothing to log (not a skill call, or unparseable) — allow and exit.
[ -z "${SKILL:-}" ] && exit 0
[ "$SKILL" = "-" ] && exit 0

PROJECT=$(basename "${CWD:-$PWD}" 2>/dev/null || echo "unknown")
[ "$PROJECT" = "-" ] && PROJECT="unknown"
[ "$ARGS" = "-" ] && ARGS=""

# Emit one JSONL line. Use python for safe JSON escaping of the fields.
python3 -c "
import json, datetime
print(json.dumps({
    'ts': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'skill': '''$SKILL''',
    'project': '''$PROJECT''',
    'args': '''$ARGS''',
}))
" >> "$WORKFLOW_LOG" 2>/dev/null || true

exit 0
