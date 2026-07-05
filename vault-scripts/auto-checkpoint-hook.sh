#!/bin/bash
# Claude Code Stop hook: auto-checkpoint uncommitted work as a git stash.
# Uses `git stash create` + `git stash store` to save state WITHOUT modifying
# the working tree — the stash entry exists purely as a safety net.
set -euo pipefail

HOOKS_LOG="$HOME/vault/logs/hooks.jsonl"
mkdir -p "$(dirname "$HOOKS_LOG")"

hook_log() {
  local outcome="$1" detail="${2:-}"
  printf '{"ts":"%s","hook":"auto-checkpoint","outcome":"%s","detail":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$outcome" "$detail" >> "$HOOKS_LOG"
}

# Read hook input
INPUT=$(cat)

CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || true)
if [ -n "$CWD" ]; then cd "$CWD" 2>/dev/null || true; fi

# Must be in a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  hook_log "skip" "not a git repo"
  exit 0
fi

# Check for any uncommitted changes (staged, unstaged, or untracked)
if git diff --quiet HEAD 2>/dev/null && \
   git diff --cached --quiet 2>/dev/null && \
   [ -z "$(git ls-files --others --exclude-standard 2>/dev/null | head -1)" ]; then
  hook_log "skip" "clean working tree"
  exit 0
fi

# Create stash object without touching the working tree
STASH_SHA=$(git stash create "claude-auto-checkpoint" 2>/dev/null || true)

if [ -n "$STASH_SHA" ]; then
  LABEL="claude-auto-$(date +%Y%m%d-%H%M%S)"
  git stash store -m "$LABEL" "$STASH_SHA" 2>/dev/null
  hook_log "ok" "stash $LABEL (${STASH_SHA:0:8})"
else
  hook_log "skip" "stash create returned empty"
fi

# Prune old auto-checkpoints — keep the newest $KEEP claude-auto-* stashes,
# drop the rest. Manual stashes (anything without the claude-auto- label) are
# never touched. Without this, checkpoints pile up indefinitely (84 had
# accumulated by 2026-06-16). Drop highest index first so indices don't shift
# out from under pending drops.
KEEP=30
AUTO_IDX=( $(git stash list 2>/dev/null | grep 'claude-auto-' | sed -E 's/^stash@\{([0-9]+)\}:.*/\1/') )
if [ "${#AUTO_IDX[@]}" -gt "$KEEP" ]; then
  TO_DROP=$(printf '%s\n' "${AUTO_IDX[@]:$KEEP}" | sort -rn)
  N_DROPPED=0
  for idx in $TO_DROP; do
    git stash drop "stash@{$idx}" >/dev/null 2>&1 && N_DROPPED=$((N_DROPPED+1)) || true
  done
  [ "$N_DROPPED" -gt 0 ] && hook_log "prune" "dropped $N_DROPPED old auto-checkpoint stash(es), kept newest $KEEP"
fi
