#!/bin/bash
# Daily cron: export all unexported Claude Code sessions, then update QMD index.
# Intended to run once daily via launchd or crontab.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPORT_SCRIPT="$SCRIPT_DIR/export-session.py"
PROJECTS_BASE="$HOME/.claude/projects"
VAULT_SESSIONS="$HOME/vault/sessions"
LOG="$HOME/vault/logs/daily-session-sync.log"

mkdir -p "$(dirname "$LOG")" "$VAULT_SESSIONS"

exec >> "$LOG" 2>&1
echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="

exported=0
skipped=0
noise=0
failed=0

# Find top-level session JSONL files (skip subagents)
while IFS= read -r jsonl; do
  # Extract session ID (filename without .jsonl)
  session_id="$(basename "$jsonl" .jsonl)"
  id_prefix="${session_id:0:8}"

  # Skip if already exported (vault has a file ending with this ID prefix)
  if ls "$VAULT_SESSIONS"/*"${id_prefix}.md" &>/dev/null; then
    skipped=$((skipped + 1))
    continue
  fi

  # Export — returns empty string for noise-only or unchanged sessions
  output=$(python3 "$EXPORT_SCRIPT" "$jsonl" 2>&1)
  if [ $? -ne 0 ]; then
    echo "  FAILED: $jsonl"
    failed=$((failed + 1))
  elif echo "$output" | grep -q "^Exported:"; then
    exported=$((exported + 1))
    echo "$output"
  else
    noise=$((noise + 1))
  fi
done < <(find "$PROJECTS_BASE" -name "*.jsonl" -type f -not -path "*/subagents/*" 2>/dev/null)

echo "Exported: $exported | Skipped: $skipped | Noise: $noise | Failed: $failed"

# Update QMD index
if command -v qmd &>/dev/null; then
  echo "Updating QMD index..."
  qmd update 2>/dev/null || true
  echo "Embedding vectors..."
  qmd embed 2>/dev/null || true
  echo "QMD sync done."
else
  echo "qmd not found, skipping index update."
fi

# ── Log rotation ────────────────────────────────────────────────────────
HOOKS_LOG="$HOME/vault/logs/hooks.jsonl"
if [ -f "$HOOKS_LOG" ]; then
  line_count=$(wc -l < "$HOOKS_LOG" | tr -d ' ')
  if [ "$line_count" -gt 5000 ]; then
    # Keep last 2000 lines, archive the rest
    tail -2000 "$HOOKS_LOG" > "${HOOKS_LOG}.tmp"
    mv "${HOOKS_LOG}.tmp" "$HOOKS_LOG"
    echo "Rotated hooks.jsonl: $line_count -> 2000 lines"
  fi
fi

# Rotate daily sync log too
if [ -f "$LOG" ]; then
  log_lines=$(wc -l < "$LOG" | tr -d ' ')
  if [ "$log_lines" -gt 2000 ]; then
    tail -500 "$LOG" > "${LOG}.tmp"
    mv "${LOG}.tmp" "$LOG"
  fi
fi

echo "=== Done ==="
