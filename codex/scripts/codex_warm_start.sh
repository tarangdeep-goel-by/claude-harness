#!/usr/bin/env bash
# Codex-native entrypoint for the shared warm-start implementation.
# The installed runtime path is ~/.codex/scripts/codex_warm_start.sh; this wrapper avoids depending
# on ~/.claude while reusing the repository's single warm-start source.
set -uo pipefail

SCRIPT_PATH="$(
  python3 - "$0" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
)"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WARM_START="$REPO_ROOT/claude/scripts/warm-start.sh"

if [ ! -x "$WARM_START" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Codex warm-start unavailable: %s"}}\n' "$WARM_START"
  exit 0
fi

exec "$WARM_START"
