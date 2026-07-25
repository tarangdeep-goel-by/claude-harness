#!/bin/bash
# PostToolUse hook on Write|Edit: run project tests in background after source file changes.
# Debounced to max once per 30 seconds. Results logged to hooks.jsonl.
set -euo pipefail

HOOKS_LOG="$HOME/vault/logs/hooks.jsonl"
LOCK_FILE="/tmp/claude-autotest.lock"
RESULT_FILE="/tmp/claude-autotest-result.txt"
DEBOUNCE_SECS=30

mkdir -p "$(dirname "$HOOKS_LOG")"

INPUT=$(cat)

# Extract the file path from tool input
FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
inp = d.get('input', {})
print(inp.get('file_path', inp.get('filePath', '')))
" 2>/dev/null || true)

[ -z "$FILE_PATH" ] && exit 0

# Skip non-source files
case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx|*.py|*.go|*.rs|*.rb|*.java|*.kt|*.swift|*.dart) ;;
  *) exit 0 ;;
esac

# Skip test files themselves (avoid infinite loops if tests generate output)
case "$FILE_PATH" in
  *test*|*spec*|*_test.*|*.test.*|*.spec.*) exit 0 ;;
esac

# Debounce: skip if tests ran within the last N seconds
if [ -f "$LOCK_FILE" ]; then
  LAST_RUN=$(cat "$LOCK_FILE" 2>/dev/null || echo "0")
  NOW=$(date +%s)
  if [ $((NOW - LAST_RUN)) -lt $DEBOUNCE_SECS ]; then
    exit 0
  fi
fi

# Find project root by walking up from the file
DIR=$(dirname "$FILE_PATH")
TEST_CMD=""
PROJECT_ROOT=""

while [ "$DIR" != "/" ] && [ "$DIR" != "." ]; do
  if [ -f "$DIR/package.json" ]; then
    PROJECT_ROOT="$DIR"
    # Detect package manager
    if [ -f "$DIR/bun.lockb" ] || [ -f "$DIR/bun.lock" ]; then TEST_CMD="bun test"
    elif [ -f "$DIR/pnpm-lock.yaml" ]; then TEST_CMD="pnpm test"
    elif [ -f "$DIR/yarn.lock" ]; then TEST_CMD="yarn test"
    else TEST_CMD="npm test"; fi
    break
  elif [ -f "$DIR/pyproject.toml" ] || [ -f "$DIR/pytest.ini" ] || [ -f "$DIR/setup.py" ]; then
    PROJECT_ROOT="$DIR"
    TEST_CMD="python3 -m pytest -x -q"
    break
  elif [ -f "$DIR/go.mod" ]; then
    PROJECT_ROOT="$DIR"
    TEST_CMD="go test ./..."
    break
  elif [ -f "$DIR/Cargo.toml" ]; then
    PROJECT_ROOT="$DIR"
    TEST_CMD="cargo test"
    break
  fi
  DIR=$(dirname "$DIR")
done

# No test command found — skip
if [ -z "$TEST_CMD" ] || [ -z "$PROJECT_ROOT" ]; then
  exit 0
fi

# Record timestamp for debounce
date +%s > "$LOCK_FILE"

# Run tests in background
(
  cd "$PROJECT_ROOT"
  set +e
  RESULT=$(timeout 60 sh -c "$TEST_CMD" 2>&1)
  EXIT_CODE=$?
  set -e

  # Save last result for inspection
  printf "# Auto-test at %s\n# Command: %s\n# Exit: %d\n%s\n" \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$TEST_CMD" "$EXIT_CODE" "$RESULT" > "$RESULT_FILE"

  if [ $EXIT_CODE -eq 0 ]; then
    OUTCOME="ok"
  else
    OUTCOME="fail"
  fi

  printf '{"ts":"%s","hook":"auto-test","outcome":"%s","detail":"%s in %s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$OUTCOME" "$TEST_CMD" "$(basename "$PROJECT_ROOT")" >> "$HOOKS_LOG"
) &
disown

exit 0
