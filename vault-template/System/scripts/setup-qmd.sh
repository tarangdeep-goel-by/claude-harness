#!/bin/bash
# ============================================================================
# setup-qmd.sh — Set up QMD session infrastructure for Claude Code
# ============================================================================
#
# WHAT IS QMD?
#   QMD (Query Markdown) is a local semantic search engine over markdown files.
#   It indexes your vault notes, Claude Code session transcripts, and project docs
#   into a searchable database with BM25 keyword search + vector embeddings.
#   You query it like: qmd query "why did we choose cohort targeting" -c projects
#
# HOW THE SESSION PIPELINE WORKS:
#
#   ┌─────────────────────────────────────────────────────────────┐
#   │ You use Claude Code (any session, any project)              │
#   └─────────────────┬───────────────────────────────────────────┘
#                     │ session ends
#                     ▼
#   ┌─────────────────────────────────────────────────────────────┐
#   │ session-export-hook.sh (Stop hook — runs automatically)     │
#   │  → Finds the session JSONL (~/.claude/projects/*/UUID.jsonl)│
#   │  → Runs export-session.py to convert JSONL → clean markdown │
#   │  → Saves to ~/vault/sessions/YYYY-MM-DD_project_UUID.md    │
#   │  → Runs learning-detector.py to extract patterns            │
#   │  → Runs qmd update + qmd embed to reindex                  │
#   └─────────────────────────────────────────────────────────────┘
#
#   ┌─────────────────────────────────────────────────────────────┐
#   │ Next session starts                                         │
#   └─────────────────┬───────────────────────────────────────────┘
#                     │ SessionStart hook
#                     ▼
#   ┌─────────────────────────────────────────────────────────────┐
#   │ warm-start.sh (SessionStart hook — runs automatically)      │
#   │  → Gathers git state, stack info, recent commits            │
#   │  → Finds most recent session transcript for this project    │
#   │  → Injects as context so Claude knows what happened last    │
#   └─────────────────────────────────────────────────────────────┘
#
#   ┌─────────────────────────────────────────────────────────────┐
#   │ daily-session-sync.sh (7 AM cron — runs daily)              │
#   │  → Scans ALL session JSONLs, exports any that were missed   │
#   │  → Catches sessions where the Stop hook didn't fire         │
#   │  → Rebuilds full QMD index                                  │
#   └─────────────────────────────────────────────────────────────┘
#
#   ┌─────────────────────────────────────────────────────────────┐
#   │ precompact-hook.sh (PreCompact hook — runs before compaction│
#   │  → Exports transcript BEFORE context window is truncated    │
#   │  → Ensures long sessions aren't lost to compaction          │
#   └─────────────────────────────────────────────────────────────┘
#
# OTHER HOOKS INSTALLED:
#   memory-sync-hook.sh    → Syncs session insights to memory files via Gemini
#   auto-checkpoint-hook.sh → Git stash of uncommitted work on session end
#   completion-check-hook.sh → Scans for placeholder code before session ends
#   file-guard-hook.sh     → Blocks access to sensitive files (.env, keys)
#   block-dangerous-hook.sh → Blocks destructive bash commands (rm -rf, etc.)
#   allow-python-hook.sh   → Auto-allows python3 commands in Bash tool
#   persist-env-hook.sh    → Persists env vars across Bash calls in a session
#   subagent-context-hook.sh → Injects project conventions into subagents
#
# QMD COLLECTIONS CONFIGURED:
#   sessions     → ~/vault/sessions/              Claude Code transcripts (auto-exported)
#   daily        → vault-work/Daily/              Your PM workday — scratchpad, meetings, recordings
#   projects     → vault-work/Notes/              Project specs, decisions, research
#   handoffs     → vault-work/System/handoffs/    Session continuity notes from /wrap-up
#   meta         → vault-work/Meta/               Memory file, agent messages
#   claude-plans → ~/.claude/plans/              Plan mode outputs
#
# QUERYING:
#   # Search across everything
#   qmd query "renewal notification decision" -c daily -c sessions -c projects
#
#   # Search specific collection
#   qmd query "what did Viral say" -c daily
#   qmd query "what did Claude help with" -c sessions
#
#   # Browse
#   qmd ls sessions       # list all session transcripts
#   qmd ls projects       # list all project docs
#   qmd status            # index health
#
# WHAT THIS SCRIPT DOES:
#   1. Creates vault directory structure (~/vault/sessions, logs, etc.)
#   2. Configures QMD collections (sessions, daily, projects, handoffs)
#   3. Installs hook scripts to ~/vault/scripts/
#   4. Installs warm-start to ~/.claude/scripts/
#   5. Sets up daily session sync cron (7 AM)
#   6. Backfills existing sessions
#   7. Builds QMD index
#
# PREREQUISITES:
#   - qmd installed (npm install -g @tobilu/qmd)
#   - Claude Code installed
#   - Node.js 22+
#
# USAGE:
#   bash System/scripts/setup-qmd.sh

set -euo pipefail

VAULT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PORTABLE_HOOKS="$VAULT_DIR/System/portable-hooks"
VAULT_HOME="$HOME/vault"
CLAUDE_DIR="$HOME/.claude"

echo "============================================"
echo "  QMD Session Infrastructure Setup"
echo "  Vault: $VAULT_DIR"
echo "============================================"
echo ""

# ── 1. Check prerequisites ──────────────────────────────────────────────

echo "==> [1/7] Checking prerequisites..."

if ! command -v qmd &>/dev/null; then
  echo "  ✗ QMD not found. Install: npm install -g @tobilu/qmd"
  exit 1
fi
echo "  ✓ QMD $(qmd --version 2>/dev/null || echo 'installed')"

if ! command -v python3 &>/dev/null; then
  echo "  ✗ Python3 not found"
  exit 1
fi
echo "  ✓ Python3"

echo ""

# ── 2. Create vault directory structure ──────────────────────────────────

echo "==> [2/7] Creating vault directories..."

mkdir -p "$VAULT_HOME/sessions"
mkdir -p "$VAULT_HOME/daily"
mkdir -p "$VAULT_HOME/notes"
mkdir -p "$VAULT_HOME/logs"
mkdir -p "$VAULT_HOME/scripts"
mkdir -p "$CLAUDE_DIR/scripts"

echo "  ✓ ~/vault/sessions/"
echo "  ✓ ~/vault/daily/"
echo "  ✓ ~/vault/notes/"
echo "  ✓ ~/vault/logs/"
echo "  ✓ ~/vault/scripts/"
echo "  ✓ ~/.claude/scripts/"
echo ""

# ── 3. Configure QMD collections ────────────────────────────────────────

echo "==> [3/7] Configuring QMD collections..."

QMD_CONFIG="$HOME/.config/qmd/index.yml"
mkdir -p "$(dirname "$QMD_CONFIG")"

cat > "$QMD_CONFIG" << QMDEOF
collections:
  sessions:
    path: $VAULT_HOME/sessions
    pattern: "**/*.md"
    context:
      "": Claude Code conversation transcripts with YAML frontmatter containing date, project, session_id, model.
  daily:
    path: $VAULT_DIR/Daily
    pattern: "**/*.md"
    context:
      "": Daily scratchpad notes, meeting notes, and transcriptions from your daily work.
  projects:
    path: $VAULT_DIR/Notes
    pattern: "**/*.md"
    context:
      "": Project knowledge bases — specs, decisions, research, meeting notes. Each subfolder is a project.
  handoffs:
    path: $VAULT_DIR/System/handoffs
    pattern: "**/*.md"
    context:
      "": Session handoff notes for continuity between Claude Code sessions.
  meta:
    path: $VAULT_DIR/Meta
    pattern: "**/*.md"
    context:
      "": Vault metadata — persistent memory, agent message board, vault conventions.
  claude-plans:
    path: $CLAUDE_DIR/plans
    pattern: "*.md"
    context:
      "": Claude Code plan mode outputs. Each file is a session's implementation plan.
QMDEOF

echo "  ✓ QMD config written to $QMD_CONFIG"
echo ""
echo "  Collections:"
echo "    sessions     → ~/vault/sessions/ (Claude Code transcripts)"
echo "    daily        → vault-work/Daily/ (your PM workday)"
echo "    projects     → vault-work/Notes/ (project knowledge)"
echo "    handoffs     → vault-work/System/handoffs/ (session continuity)"
echo "    meta         → vault-work/Meta/ (memory, agent messages)"
echo "    claude-plans → ~/.claude/plans/ (plan mode outputs)"
echo ""

# ── 4. Install hook scripts ─────────────────────────────────────────────

echo "==> [4/7] Installing hook scripts..."

# Session lifecycle hooks → ~/vault/scripts/
HOOKS=(
  session-export-hook.sh
  export-session.py
  precompact-hook.sh
  memory-sync-hook.sh
  memory-sync.py
  learning-detector.py
  daily-session-sync.sh
  auto-checkpoint-hook.sh
  completion-check-hook.sh
  file-guard-hook.sh
  block-dangerous-hook.sh
  allow-python-hook.sh
  persist-env-hook.sh
  subagent-context-hook.sh
)

for hook in "${HOOKS[@]}"; do
  src="$PORTABLE_HOOKS/$hook"
  dst="$VAULT_HOME/scripts/$hook"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
    chmod +x "$dst"
    echo "  ✓ $hook"
  else
    echo "  ⚠ $hook (not found in portable-hooks/)"
  fi
done

# Warm-start → ~/.claude/scripts/ as a SYMLINK to the single source of truth in
# claude-harness (the harness install.sh owns hook deployment; one source → no drift).
# warm-start.sh was retired from portable-hooks/ on 2026-07-02 — it lives ONLY in
# claude-harness now. (The other portable-hooks are pending the same migration.)
HARNESS_WARMSTART="$HOME/code/claude-harness/claude/scripts/warm-start.sh"
if [ -f "$HARNESS_WARMSTART" ]; then
  ln -sfn "$HARNESS_WARMSTART" "$CLAUDE_DIR/scripts/warm-start.sh"
  echo "  ✓ warm-start.sh → symlink to claude-harness (single source)"
else
  echo "  ⚠ claude-harness not found ($HARNESS_WARMSTART) — run its install.sh to deploy warm-start.sh"
fi

echo ""

# ── 5. Set up daily sync cron ───────────────────────────────────────────

echo "==> [5/7] Setting up daily session sync..."

PLIST_NAME="com.vault.daily-session-sync"
PLIST_SRC="$VAULT_DIR/System/scripts/$PLIST_NAME.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

# Create the LaunchAgent plist
cat > "$PLIST_SRC" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>$VAULT_HOME/scripts/daily-session-sync.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>7</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/vault-daily-session-sync.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/vault-daily-session-sync.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
PLISTEOF

# Unload old if exists, then load new
launchctl unload "$PLIST_DST" 2>/dev/null || true
ln -sf "$PLIST_SRC" "$PLIST_DST"
launchctl load "$PLIST_DST"

echo "  ✓ Daily sync cron installed (runs at 7:00 AM)"
echo "    Exports all Claude Code sessions → ~/vault/sessions/"
echo "    Rebuilds QMD index"
echo ""

# ── 6. Backfill existing sessions ───────────────────────────────────────

echo "==> [6/7] Backfilling existing sessions..."

PROJECTS_BASE="$CLAUDE_DIR/projects"
EXPORT_SCRIPT="$VAULT_HOME/scripts/export-session.py"

if [ -f "$EXPORT_SCRIPT" ] && [ -d "$PROJECTS_BASE" ]; then
  exported=0
  skipped=0
  failed=0

  while IFS= read -r jsonl; do
    session_id="$(basename "$jsonl" .jsonl)"
    id_prefix="${session_id:0:8}"

    # Skip if already exported
    if ls "$VAULT_HOME/sessions/"*"${id_prefix}.md" &>/dev/null 2>&1; then
      skipped=$((skipped + 1))
      continue
    fi

    # Skip small files (< 20 lines = noise)
    lines=$(wc -l < "$jsonl" 2>/dev/null | tr -d ' ')
    if [ "${lines:-0}" -lt 20 ]; then
      skipped=$((skipped + 1))
      continue
    fi

    output=$(python3 "$EXPORT_SCRIPT" "$jsonl" 2>&1) && exported=$((exported + 1)) || failed=$((failed + 1))
  done < <(find "$PROJECTS_BASE" -name "*.jsonl" -type f -not -path "*/subagents/*" 2>/dev/null)

  echo "  Exported: $exported | Skipped: $skipped | Failed: $failed"
else
  echo "  ⚠ No sessions to backfill (export script or projects dir missing)"
fi

echo ""

# ── 7. Build QMD index ──────────────────────────────────────────────────

echo "==> [7/7] Building QMD index..."

qmd update 2>/dev/null && echo "  ✓ Index updated" || echo "  ⚠ Index update failed"
qmd embed 2>/dev/null && echo "  ✓ Embeddings computed" || echo "  ⚠ Embedding failed"

echo ""

# ── Done ─────────────────────────────────────────────────────────────────

echo "============================================"
echo "  QMD Setup Complete!"
echo "============================================"
echo ""
echo "How it works:"
echo "  1. Every session end → session-export-hook.sh exports transcript to ~/vault/sessions/"
echo "  2. Every session end → QMD index auto-updates"
echo "  3. Every morning 7 AM → daily-session-sync.sh catches any missed exports"
echo "  4. Every session start → warm-start.sh injects previous session context"
echo ""
echo "Usage:"
echo "  # Search across everything (daily + sessions + projects)"
echo "  qmd query 'what was decided about renewal notifications' -c daily -c sessions -c projects"
echo ""
echo "  # Search specific collections"
echo "  qmd query 'what did Viral say about metrics' -c daily"
echo "  qmd query 'FD renewal project status' -c projects"
echo "  qmd query 'what did Claude help with yesterday' -c sessions"
echo ""
echo "  # Browsing"
echo "  qmd ls sessions     # list all session transcripts"
echo "  qmd ls daily        # list daily notes"
echo "  qmd ls projects     # list project docs"
echo "  qmd status          # check index health"
echo ""
echo "Verify hooks are configured in ~/.claude/settings.json:"
echo "  - SessionStart → warm-start.sh"
echo "  - Stop → session-export-hook.sh, memory-sync-hook.sh"
echo "  - PreCompact → precompact-hook.sh"
echo ""
