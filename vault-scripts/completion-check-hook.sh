#!/bin/bash
# Claude Code Stop hook: scan modified files for placeholder code and stubs.
# Exit 2 = block stop (Claude resumes to fix issues).
# Checks stop_hook_active to prevent infinite loops.
set -euo pipefail

HOOKS_LOG="$HOME/vault/logs/hooks.jsonl"
mkdir -p "$(dirname "$HOOKS_LOG")"

hook_log() {
  local outcome="$1" detail="${2:-}"
  printf '{"ts":"%s","hook":"completion-check","outcome":"%s","detail":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$outcome" "$detail" >> "$HOOKS_LOG"
}

INPUT=$(cat)

# Prevent infinite loops: skip if this is a re-run after a previous block
STOP_HOOK_ACTIVE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('stop_hook_active', False))" 2>/dev/null || echo "False")
if [ "$STOP_HOOK_ACTIVE" = "True" ] || [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  hook_log "skip" "stop_hook_active=true"
  exit 0
fi

CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || true)
if [ -n "$CWD" ]; then cd "$CWD" 2>/dev/null || true; fi

# Must be in a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  hook_log "skip" "not a git repo"
  exit 0
fi

# Get files with uncommitted changes
CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null || true)
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null || true)
ALL_MODIFIED=$(printf '%s\n%s' "$CHANGED_FILES" "$STAGED_FILES" | sort -u | grep -v '^$' || true)

if [ -z "$ALL_MODIFIED" ]; then
  hook_log "skip" "no modified files"
  exit 0
fi

# Scan for placeholder/stub patterns that indicate incomplete work
# These are Claude's most common failure modes
PLACEHOLDER_PATTERNS=(
  '// \.\.\. rest'
  '// \.\.\.existing'
  '// existing code'
  '// remaining implementation'
  '// TODO: implement'
  '# \.\.\. rest'
  '# \.\.\.existing'
  '# remaining implementation'
  '# TODO: implement'
  'raise NotImplementedError'
  'pass  # placeholder'
  'pass  # TODO'
  'FIXME: implement'
  '\/\* \.\.\. \*\/'
)

# Build a single grep pattern
PATTERN=$(IFS='|'; echo "${PLACEHOLDER_PATTERNS[*]}")

ISSUES=""
ISSUE_COUNT=0

while IFS= read -r file; do
  [ -z "$file" ] && continue
  [ ! -f "$file" ] && continue

  # Skip non-text / generated files
  case "$file" in
    *.lock|*.min.js|*.min.css|*.map|*.svg|*.png|*.jpg|*.ico|*.woff*) continue ;;
    node_modules/*|dist/*|build/*|.next/*|__pycache__/*|*.pyc) continue ;;
  esac

  MATCHES=$(grep -n -E "$PATTERN" "$file" 2>/dev/null || true)
  if [ -n "$MATCHES" ]; then
    ISSUES+="$file:"$'\n'"$MATCHES"$'\n\n'
    ISSUE_COUNT=$((ISSUE_COUNT + $(echo "$MATCHES" | wc -l | tr -d ' ')))
  fi
done <<< "$ALL_MODIFIED"

if [ -n "$ISSUES" ] && [ "$ISSUE_COUNT" -gt 0 ]; then
  hook_log "block" "$ISSUE_COUNT placeholder(s) found"

  # Output feedback to stderr so Claude sees it and fixes
  cat >&2 <<EOF
⚠ Completion check found $ISSUE_COUNT placeholder/stub pattern(s) in modified files:

$ISSUES
Please replace these with actual implementations before stopping.
EOF
  exit 2
fi

hook_log "ok" "clean — $( echo "$ALL_MODIFIED" | wc -l | tr -d ' ') files checked"
exit 0
