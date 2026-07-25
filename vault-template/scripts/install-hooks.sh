#!/usr/bin/env bash
# Install vault-work git hooks. Idempotent — safe to re-run.
#
# Usage:
#   bash scripts/install-hooks.sh
#
# What it does:
#   - Copies tools/hooks/pre-commit → .git/hooks/pre-commit
#   - chmod +x the installed hook

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

SRC="tools/hooks/pre-commit"
DST=".git/hooks/pre-commit"

if [[ ! -f "$SRC" ]]; then
    echo "ERROR: $SRC not found. Are you in vault-work?" >&2
    exit 1
fi

if [[ ! -d ".git" ]]; then
    echo "ERROR: not a git repository (.git/ missing)." >&2
    exit 1
fi

cp "$SRC" "$DST"
chmod +x "$DST"
echo "✓ Installed pre-commit hook → $DST"
echo "  Source: $SRC"
echo ""
echo "Test it:"
echo "  echo \"x = 'is_settled = TRUE'\" >> /tmp/_drift_test.py"
echo "  cd $REPO_ROOT && git add /tmp/_drift_test.py 2>/dev/null"
echo "  git commit -m test  # should be blocked"
