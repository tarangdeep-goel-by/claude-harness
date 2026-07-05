#!/usr/bin/env bash
# catalog-sessions.sh — digest the last N days of Claude Code session cache into a compact catalog,
# so a returning user (veteran of Claude Code, new to this harness) can mine their OWN history to
# back-fill a fresh vault instead of starting empty. See ADOPT_FROM_HISTORY.md for the next step.
#
# READ-ONLY: reads ~/.claude/projects/*/*.jsonl (your transcripts), writes only the catalog file.
# Efficient: greps the few interesting lines per transcript (first prompt, titles) — never slurps
# whole files. Handles the leading-dash project-dir names that break bare `find`.
#   Usage:  ./catalog-sessions.sh [DAYS] [OUT_FILE]      (default: 30 → ./session-catalog.md)
set -uo pipefail
DAYS="${1:-30}"
OUT="${2:-./session-catalog.md}"
PROJ="$HOME/.claude/projects"
[ -d "$PROJ" ] || { echo "no ~/.claude/projects — nothing to catalog"; exit 1; }
command -v jq >/dev/null || { echo "jq required"; exit 1; }
# project dir names are the cwd with '/' rewritten to '-' (and real dashes are ambiguous), so we
# DON'T try to reconstruct an exact path — just show the slug honestly.

total=0
{
  echo "# Claude session catalog — last $DAYS days"
  echo "_generated $(date +%Y-%m-%d) · source ~/.claude/projects · read-only digest_"
  echo
  echo "Per working directory: the sessions Claude ran there recently, newest first, with each"
  echo "session's auto-title and opening goal. Use this to cluster work into projects, then deep-read"
  echo "the few richest sessions. See ADOPT_FROM_HISTORY.md."
  echo
  for d in "$PROJ"/*/; do
    name="$(basename "$d")"
    # absolute path avoids the leading-dash-as-option trap; -mtime windows to last N days
    files="$(find "$d" -maxdepth 1 -name '*.jsonl' -mtime -"$DAYS" 2>/dev/null)"
    [ -n "$files" ] || continue
    # sort newest-first by mtime
    sorted="$(echo "$files" | while read -r f; do [ -n "$f" ] && printf '%s\t%s\n' "$(stat -f %m "$f" 2>/dev/null)" "$f"; done | sort -rn | cut -f2-)"
    cnt="$(echo "$sorted" | grep -c . )"
    echo "## $name"
    echo "_${cnt} session(s) · project dir slug: \`$name\` (dashes = path separators)_"
    echo
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      sid="$(basename "$f" .jsonl)"
      dt="$(date -r "$f" +%Y-%m-%d 2>/dev/null)"
      title="$(grep '"type":"ai-title"' "$f" 2>/dev/null | tail -1 | jq -r '.aiTitle // .title // .content // empty' 2>/dev/null | tr '\n' ' ' | cut -c1-90)"
      # the real opening prompt = first user line whose content is a STRING (array-content lines
      # are injected hook context / tool results, not what the human typed)
      first="$(grep '"type":"user"' "$f" 2>/dev/null | head -40 | jq -r 'select((.content|type)=="string") | .content' 2>/dev/null | grep -v '^$' | head -1 | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-200)"
      echo "- **$dt** \`${sid:0:8}\` — ${title:-untitled}"
      [ -n "$first" ] && echo "  - opening goal: ${first}"
      total=$((total+1))
    done <<< "$sorted"
    echo
  done
  echo "---"
  echo "_${total} sessions cataloged. Next: ADOPT_FROM_HISTORY.md → turn this into vault start-offs._"
} > "$OUT"
echo "✓ wrote $OUT — $total sessions across the last $DAYS days"
