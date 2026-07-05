#!/bin/bash
# Claude Code PreToolUse hook: enforce per-task git WORKTREES for shared ~/code repos.
#
# Why: multiple chats edit the same repos in parallel. Editing the SHARED PRIMARY
# checkout means one chat's WIP (and a stray `git add -A`) clobbers another's.
# So Write/Edit to an enforced repo's primary checkout is BLOCKED — work in a
# per-task worktree instead (tools/worktree.sh).
#
# Scope: the ~/code dev repos below. The vault (~/Documents/vault-work) is EXEMPT
# (it is the orchestration home — hooks, the lib symlink, QMD index, daily_refresh
# all assume its canonical path). Edits through the vault's lib/sm_analytics
# SYMLINK resolve (realpath) to ~/code/sm-analytics → correctly blocked.
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

CODE="$HOME/code"
# Enforced canonical PRIMARY checkouts. Worktrees live elsewhere
# (~/code/.worktrees/… or ~/code/<repo>-<name>) so they never match these prefixes.
REPOS="${WORKTREE_GUARD_REPOS:-sm-analytics comms-automation stable-flutter stablemoney-platform cac-pod}"  # adopters: export WORKTREE_GUARD_REPOS="repoA repoB"; unset = the owner's repos (no change for the owner)

for r in $REPOS; do
  prim="$CODE/$r"
  case "$REAL/" in
    "$prim"/*)
      REASON="🌳 Worktree guard: \"$REAL\"
is in the SHARED PRIMARY checkout of '$r' — editing it here risks clobbering another chat's work.
Create/use a per-task worktree instead:
    cd \$HOME/Documents/vault-work && tools/worktree.sh new $r <slug>
then edit the same file under \$HOME/code/.worktrees/${r}__<slug>/ .
(The vault is exempt; lib edits go through the worktree, not the lib/ symlink.)"
      LOG="$HOME/vault/logs/workflow.jsonl"
      mkdir -p "$(dirname "$LOG")"
      echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"skill\":\"hook:worktree-guard\",\"project\":\"workspace\",\"task\":\"blocked $TOOL_NAME on primary checkout: $r\"}" >> "$LOG"
      jq -n --arg reason "$REASON" '{"decision":"deny","reason":$reason}'
      exit 0
      ;;
  esac
done

exit 0
