#!/bin/bash
# Claude Code PreToolUse hook: enforce per-task git WORKTREES for shared ~/code repos.
#
# Why: multiple chats edit the same repos in parallel. Editing the SHARED PRIMARY
# checkout means one chat's WIP (and a stray `git add -A`) clobbers another's.
# So Write/Edit to an enforced repo's primary checkout is BLOCKED — work in a
# per-task worktree instead (tools/worktree.sh).
#
# Scope: the dev repos listed in $WORKTREE_GUARD_REPOS below (space-separated
# repo names under $WORKTREE_GUARD_CODE, which defaults to ~/Documents/Projects).
# Opt-in — empty by default, so the hook is a no-op until you list repos.
# Worktrees live elsewhere (under $WORKTREE_GUARD_CODE/.worktrees/…) so they
# never match the primary-checkout prefix and aren't blocked.
#
# Reads JSON on stdin (.tool_name, .tool_input.file_path|.path).
# Emits {"decision":"deny","reason":...} to block; silent exit 0 to allow.
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Only writes matter — reading the primary checkout is fine.
case "$TOOL_NAME" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')
[ -z "$FILE_PATH" ] && exit 0

# Resolve symlinks + relative parts. os.path.realpath handles not-yet-existing
# files (resolves the existing prefix), so new-file Writes are covered too.
REAL=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$FILE_PATH" 2>/dev/null || true)
[ -z "$REAL" ] && exit 0

CODE="${WORKTREE_GUARD_CODE:-$HOME/Documents/Projects}"
# Enforced canonical PRIMARY checkouts. Worktrees live elsewhere
# ($CODE/.worktrees/…) so they never match these prefixes.
# Empty by default — set WORKTREE_GUARD_REPOS="repoA repoB" to enable per-repo.
REPOS="${WORKTREE_GUARD_REPOS:-}"

for r in $REPOS; do
  prim="$CODE/$r"
  case "$REAL/" in
    "$prim"/*)
      REASON="🌳 Worktree guard: \"$REAL\"
is in the SHARED PRIMARY checkout of '$r' — editing it here risks clobbering another chat's work.
Create/use a per-task worktree instead:
    git -C \"$prim\" worktree add -b \"wt/\$(date +%s)-<slug>\" \"\$CODE/.worktrees/${r}-<slug>\"
then edit the same file under \$CODE/.worktrees/${r}-<slug>/ ."
      LOG="$HOME/vault/logs/workflow.jsonl"
      mkdir -p "$(dirname "$LOG")"
      echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"skill\":\"hook:worktree-guard\",\"project\":\"workspace\",\"task\":\"blocked $TOOL_NAME on primary checkout: $r\"}" >> "$LOG"
      jq -n --arg reason "$REASON" '{"decision":"deny","reason":$reason}'
      exit 0
      ;;
  esac
done

exit 0
