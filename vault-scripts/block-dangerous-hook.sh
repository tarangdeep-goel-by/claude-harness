#!/bin/bash
# PreToolUse hook on Bash: block destructive commands.
# Exit 2 = block (stderr shown to Claude as feedback).
set -euo pipefail

HOOKS_LOG="$HOME/vault/logs/hooks.jsonl"
mkdir -p "$(dirname "$HOOKS_LOG")"

INPUT=$(cat)

CMD=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('command', ''))
" 2>/dev/null || true)

[ -z "$CMD" ] && exit 0

BLOCKED=""
REASON=""

# ── rm -rf with broad targets ────────────────────────────────────────────
if echo "$CMD" | grep -qE 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f|--recursive)\s+(/|~/|\.\s|\.\.|\*|"\."|'"'"'\.'"'"')'; then
  BLOCKED="rm -rf with broad target"
  REASON="This rm command targets a broad path. Specify exact files/dirs instead."
fi

# ── git force push ───────────────────────────────────────────────────────
# Block bare `--force` / `-f`. Allow `--force-with-lease` and
# `--force-if-includes` (refuse-if-stale variants are safer than `--force`).
# Pattern: `-f` / `--force` must be a standalone token — preceded by
# whitespace (or directly after `push`) and followed by whitespace or EOL.
# `--force-with-lease` is followed by `-`, not whitespace, so it doesn't match.
if echo "$CMD" | grep -qE 'git[[:space:]]+push([[:space:]]+(-f|--force)([[:space:]]|$)|.*[[:space:]](-f|--force)([[:space:]]|$))'; then
  BLOCKED="git push --force"
  REASON="Force push can overwrite remote history. Use --force-with-lease or push normally."
fi

# ── git reset --hard ─────────────────────────────────────────────────────
if echo "$CMD" | grep -qE 'git\s+reset\s+--hard'; then
  BLOCKED="git reset --hard"
  REASON="This discards all uncommitted changes. Use git stash or git reset --soft instead."
fi

# ── git checkout/restore that discards all changes ───────────────────────
if echo "$CMD" | grep -qE 'git\s+(checkout|restore)\s+\.\s*$'; then
  BLOCKED="git checkout/restore ."
  REASON="This discards all unstaged changes. Target specific files instead."
fi

# ── git clean -f (removes untracked files) ───────────────────────────────
if echo "$CMD" | grep -qE 'git\s+clean\s+-[a-zA-Z]*f'; then
  BLOCKED="git clean -f"
  REASON="This permanently deletes untracked files. Review with git clean -n first."
fi

# ── git branch -D (force delete) ────────────────────────────────────────
if echo "$CMD" | grep -qE 'git\s+branch\s+-D\s'; then
  BLOCKED="git branch -D"
  REASON="Force-deleting a branch can lose unmerged work. Use -d (safe delete) instead."
fi

# ── SQL destructive ops ──────────────────────────────────────────────────
if echo "$CMD" | grep -qiE '(DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s+TABLE|DELETE\s+FROM\s+\w+\s*;)'; then
  BLOCKED="destructive SQL"
  REASON="Destructive SQL detected. Add a WHERE clause or confirm this is intentional."
fi

# ── docker system prune ──────────────────────────────────────────────────
if echo "$CMD" | grep -qE 'docker\s+system\s+prune'; then
  BLOCKED="docker system prune"
  REASON="This removes all unused containers, images, and volumes. Be more targeted."
fi

# ── chmod 777 recursively ────────────────────────────────────────────────
if echo "$CMD" | grep -qE 'chmod\s+(-R\s+)?777'; then
  BLOCKED="chmod 777"
  REASON="World-writable permissions are a security risk. Use more restrictive permissions."
fi

if [ -n "$BLOCKED" ]; then
  printf '{"ts":"%s","hook":"block-dangerous","outcome":"block","detail":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$BLOCKED" >> "$HOOKS_LOG"
  echo "BLOCKED: $REASON" >&2
  exit 2
fi

exit 0
