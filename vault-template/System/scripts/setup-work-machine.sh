#!/usr/bin/env bash
# ============================================================================
# setup-work-machine.sh — Bootstrap Claude Code Infrastructure on Work Machine
# ============================================================================
#
# This script sets up the full Claude Code hook infrastructure, QMD search
# engine, and Obsidian vault structure on a new work machine.
#
# Architecture:
#   ~/vault/                    <- Session vault (transcripts, logs, hooks, scripts)
#   ~/Documents/vault-work/     <- Knowledge vault (Obsidian PM vault)
#   ~/.claude/                  <- Claude Code config, warm-start, plans
#   ~/.config/qmd/              <- QMD search engine config
#
# Usage:
#   chmod +x setup-work-machine.sh
#   ./setup-work-machine.sh
#
# The script is idempotent — safe to run multiple times.
# ============================================================================

set -euo pipefail

# ── Colors & Helpers ─────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
section() { echo -e "\n${BOLD}=== $* ===${NC}"; }

# Track what was done for final summary
ACTIONS=()
action() { ACTIONS+=("$1"); }

# ============================================================================
# 1. CREATE DIRECTORY STRUCTURE
# ============================================================================
section "Directory Structure"

dirs=(
  "$HOME/vault/sessions"
  "$HOME/vault/daily"
  "$HOME/vault/notes"
  "$HOME/vault/logs"
  "$HOME/vault/scripts"
  "$HOME/.claude/scripts"
  "$HOME/.claude/plans"
  "$HOME/.claude/session-env"
  "$HOME/.claude/projects"
  "$HOME/.claude/skills"
  "$HOME/Documents/vault-work/Daily"
  "$HOME/Documents/vault-work/Notes"
  "$HOME/Documents/vault-work/Categories"
  "$HOME/Documents/vault-work/Subjects"
  "$HOME/Documents/vault-work/Meta"
  "$HOME/Documents/vault-work/System/scripts"
  "$HOME/Documents/vault-work/System/templates"
  "$HOME/Documents/vault-work/System/dashboards"
  "$HOME/Documents/vault-work/System/handoffs"
  "$HOME/Documents/vault-work/System/docs"
  "$HOME/Documents/vault-work/.obsidian"
)

for dir in "${dirs[@]}"; do
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    info "Created $dir"
    action "Created directory: $dir"
  fi
done
success "Directory structure ready"

# Initialize learnings queue if missing
touch "$HOME/vault/learnings-queue.jsonl" 2>/dev/null || true

# ============================================================================
# 2. INSTALL DEPENDENCIES
# ============================================================================
section "Dependencies"

# Check for Homebrew
if ! command -v brew &>/dev/null; then
  error "Homebrew not installed. Install from https://brew.sh first."
  exit 1
fi
success "Homebrew found"

# Install packages if missing
install_brew() {
  local pkg="$1"
  if brew list "$pkg" &>/dev/null; then
    success "$pkg already installed"
  else
    info "Installing $pkg..."
    brew install "$pkg"
    action "Installed $pkg via Homebrew"
    success "$pkg installed"
  fi
}

# QMD — on-device search engine over vault content (github.com/tobi/qmd).
# Installs via npm/bun. Needs Node >=22 or Bun; on macOS also `brew install sqlite`.
# First use auto-downloads ~2GB of on-device models to ~/.cache/qmd.
# Without qmd, /recall and warm-start context will not work (warm-start degrades gracefully).
if command -v qmd &>/dev/null; then
  success "qmd already installed"
elif command -v bun &>/dev/null; then
  action "installing qmd via bun (bun install -g @tobilu/qmd)"
  bun install -g @tobilu/qmd && success "qmd installed" || warn "qmd install failed — run manually: bun install -g @tobilu/qmd"
elif command -v npm &>/dev/null; then
  action "installing qmd via npm (npm install -g @tobilu/qmd)"
  npm install -g @tobilu/qmd && success "qmd installed" || warn "qmd install failed — run manually: npm install -g @tobilu/qmd"
else
  warn "qmd not found and no npm/bun. Install Node >=22 or Bun, then: npm install -g @tobilu/qmd (github.com/tobi/qmd)"
  action "MANUAL: install Node/Bun, then npm install -g @tobilu/qmd"
fi

# jq — used by hooks for JSON parsing
install_brew "jq"

# python3 — used by export/learning-detector scripts
if command -v python3 &>/dev/null; then
  success "python3 already installed ($(python3 --version 2>&1))"
else
  install_brew "python3"
fi

# ffmpeg & whisper-cpp — for audio transcription workflows
install_brew "ffmpeg"
if brew list whisper-cpp &>/dev/null; then
  success "whisper-cpp already installed"
else
  info "Installing whisper-cpp..."
  brew install whisper-cpp
  action "Installed whisper-cpp"
  success "whisper-cpp installed"
fi

# tmux — for long-running process management
install_brew "tmux"

# ============================================================================
# 3. COPY HOOK SCRIPTS
# ============================================================================
section "Hook Scripts"

info "The engine (hooks, warm-start, skills) is SYMLINKED by claude-harness/install.sh — not copied."
info "This section only VERIFIES they're present. If any are MISSING, run:"
info "  (cd ~/code/claude-harness && ./install.sh)"
echo ""

# List of all hook scripts that need to be present
HOOK_SCRIPTS=(
  # PreToolUse hooks — safety gates
  "file-guard-hook.sh"         # Blocks access to .env, SSH keys, credentials
  "block-dangerous-hook.sh"    # Blocks rm -rf /, git push --force, etc.

  # PostToolUse hooks — background automation
  "auto-test-hook.sh"          # Runs project tests after source file edits

  # PermissionRequest hooks — auto-allow safe commands
  "allow-python-hook.sh"       # Auto-allows python3 commands

  # PreCompact hooks — save context before truncation
  "precompact-hook.sh"         # Exports full transcript before compaction

  # Stop hooks — session teardown
  "completion-check-hook.sh"   # Scans for placeholder/stub code
  "auto-checkpoint-hook.sh"    # Creates git stash of uncommitted work
  "session-export-hook.sh"     # Exports session transcript to markdown (UPDATE PATHS)

  # SubagentStart hooks — inject context
  "subagent-context-hook.sh"   # Injects project conventions into subagents

  # SessionStart hooks — environment setup
  "persist-env-hook.sh"        # Sets Docker env vars, PATH, etc.
)

PYTHON_SCRIPTS=(
  "export-session.py"          # Converts JSONL sessions to markdown (UPDATE PATHS)
  "learning-detector.py"       # Regex pattern-based learning detection
)

echo "Shell hook scripts to copy:"
for script in "${HOOK_SCRIPTS[@]}"; do
  if [ -f "$HOME/vault/scripts/$script" ]; then
    success "  $script (already present)"
  else
    warn "  $script (MISSING — run claude-harness/install.sh to symlink it)"
  fi
done

echo ""
echo "Python scripts to copy:"
for script in "${PYTHON_SCRIPTS[@]}"; do
  if [ -f "$HOME/vault/scripts/$script" ]; then
    success "  $script (already present)"
  else
    warn "  $script (MISSING — run claude-harness/install.sh to symlink it)"
  fi
done

# Make all scripts executable
chmod +x "$HOME/vault/scripts/"*.sh 2>/dev/null || true
chmod +x "$HOME/vault/scripts/"*.py 2>/dev/null || true

echo ""
info "No manual path edits needed — the scripts resolve \$HOME/vault paths dynamically."

# ============================================================================
# 4. COPY WARM-START
# ============================================================================
section "Warm-Start Script"

WARM_START="$HOME/.claude/scripts/warm-start.sh"
if [ -f "$WARM_START" ]; then
  success "warm-start.sh already present"
else
  warn "warm-start.sh MISSING — run claude-harness/install.sh to symlink it"
  action "MANUAL: (cd ~/code/claude-harness && ./install.sh)"
fi

# ============================================================================
# 5. DOWNLOAD WHISPER MODELS
# ============================================================================
section "Whisper Models"

WHISPER_DIR="$HOME/.local/share/whisper-models"
mkdir -p "$WHISPER_DIR"

download_model() {
  local filename="$1"
  local url="$2"

  if [ -f "$WHISPER_DIR/$filename" ]; then
    success "$filename already downloaded"
  else
    info "Downloading $filename (this may take a while)..."
    if curl -L --progress-bar -o "$WHISPER_DIR/$filename" "$url"; then
      action "Downloaded $filename"
      success "$filename downloaded"
    else
      error "Failed to download $filename"
      warn "Download manually: curl -L -o $WHISPER_DIR/$filename $url"
      action "MANUAL: Download $filename"
    fi
  fi
}

download_model "ggml-large-v3-turbo.bin" \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"

download_model "ggml-silero-v6.2.0.bin" \
  "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin"

# ============================================================================
# 6. CONFIGURE QMD
# ============================================================================
section "QMD Configuration"

QMD_CONFIG_DIR="$HOME/.config/qmd"
QMD_CONFIG="$QMD_CONFIG_DIR/index.yml"
mkdir -p "$QMD_CONFIG_DIR"

# Write QMD index.yml for the work machine with both vaults
cat > "$QMD_CONFIG" << 'QMDEOF'
# QMD Index Configuration — Work Machine
# Indexes both the session vault (~/vault) and the knowledge vault (~/Documents/vault-work)
collections:
  # ── Session Vault (~/vault) ──────────────────────────────────────────────
  sessions:
    path: ~/vault/sessions
    pattern: "**/*.md"
    context:
      "": Claude Code conversation transcripts with YAML frontmatter containing date, project, session_id, model.
  daily:
    path: ~/vault/daily
    pattern: "**/*.md"
    context:
      "": Daily journal entries from Claude Code sessions.
  vault-notes:
    path: ~/vault/notes
    pattern: "**/*.md"
    context:
      "": Permanent knowledge notes, project docs, learnings.

  # ── Knowledge Vault (~/Documents/vault-work) ────────────────────────────
  work-daily:
    path: ~/Documents/vault-work/Daily
    pattern: "**/*.md"
    context:
      "": Daily capture notes from Obsidian PM vault.
  projects:
    path: ~/Documents/vault-work/Notes
    pattern: "**/*.md"
    context:
      "": Project notes, meeting notes, and work documentation.
  handoffs:
    path: ~/Documents/vault-work/System/handoffs
    pattern: "**/*.md"
    context:
      "": Session handoff notes for continuity between Claude Code sessions.

  # ── Claude Plans ─────────────────────────────────────────────────────────
  claude-plans:
    path: ~/.claude/plans
    pattern: "*.md"
    context:
      "": Claude Code plan mode outputs with implementation steps and architectural decisions.
QMDEOF

success "QMD config written to $QMD_CONFIG"
action "Wrote QMD index.yml"

# Initialize QMD index if qmd is available
if command -v qmd &>/dev/null; then
  info "Running initial QMD index..."
  qmd update 2>/dev/null && success "QMD index updated" || warn "QMD update failed"
  qmd embed 2>/dev/null && success "QMD embeddings generated" || warn "QMD embed failed"
else
  warn "qmd not installed — skipping index initialization"
fi

# ============================================================================
# 7. CONFIGURE CLAUDE SETTINGS.JSON HOOKS
# ============================================================================
section "Claude Code Hooks Configuration"

CLAUDE_SETTINGS="$HOME/.claude/settings.json"

# Generate the hooks config as a JSON snippet
HOOKS_JSON=$(cat << 'HOOKSEOF'
{
  "permissions": {
    "allow": []
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read|Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "~/vault/scripts/file-guard-hook.sh",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/vault/scripts/block-dangerous-hook.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "~/vault/scripts/auto-test-hook.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": "Read|Glob|Grep",
        "hooks": [
          {
            "type": "command",
            "command": "echo '{\"decision\":\"allow\"}'",
            "timeout": 2
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/vault/scripts/allow-python-hook.sh",
            "timeout": 3
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/vault/scripts/precompact-hook.sh",
            "timeout": 120
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/vault/scripts/completion-check-hook.sh",
            "timeout": 15
          },
          {
            "type": "command",
            "command": "~/vault/scripts/auto-checkpoint-hook.sh",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "~/vault/scripts/session-export-hook.sh",
            "timeout": 120
          }
        ]
      }
    ],
    "SubagentStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/vault/scripts/subagent-context-hook.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/scripts/warm-start.sh",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "~/vault/scripts/persist-env-hook.sh",
            "timeout": 5
          }
        ]
      }
    ]
  },
  "syntaxHighlightingDisabled": false,
  "alwaysThinkingEnabled": true,
  "effortLevel": "high"
}
HOOKSEOF
)

if [ -f "$CLAUDE_SETTINGS" ]; then
  warn "settings.json already exists at $CLAUDE_SETTINGS"
  info "Review and merge the hooks config manually."
  info "The required hooks config has been written to:"
  SNIPPET_FILE="$HOME/.claude/settings.json.hooks-snippet"
  echo "$HOOKS_JSON" > "$SNIPPET_FILE"
  info "  $SNIPPET_FILE"
  action "Wrote hooks snippet to $SNIPPET_FILE (merge manually)"
else
  echo "$HOOKS_JSON" > "$CLAUDE_SETTINGS"
  success "Wrote $CLAUDE_SETTINGS with full hooks config"
  action "Wrote settings.json"
fi

# ============================================================================
# 8. SET UP LAUNCHD AGENT FOR DAILY SESSION SYNC
# ============================================================================
section "Launchd Agent (Daily Session Sync)"

LAUNCHD_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.claude-harness.session-sync"
PLIST_FILE="$LAUNCHD_DIR/$PLIST_NAME.plist"

mkdir -p "$LAUNCHD_DIR"

# Create the sync script that the launchd agent will run
SYNC_SCRIPT="$HOME/vault/scripts/daily-session-sync.sh"
# Guard: install.sh symlinks the FULL (export-loop) daily-session-sync.sh into
# ~/vault/scripts. Writing through that symlink here would clobber the repo copy
# with a lesser qmd-only version — so only write this fallback if it's absent.
if [ ! -e "$SYNC_SCRIPT" ]; then
cat > "$SYNC_SCRIPT" << 'SYNCEOF'
#!/usr/bin/env bash
# daily-session-sync.sh — Run by launchd to keep QMD index fresh
# and perform daily maintenance on the vault.
set -euo pipefail

LOG="$HOME/vault/logs/daily-sync.log"
mkdir -p "$(dirname "$LOG")"

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Daily sync started" >> "$LOG"

# Update QMD index with any new sessions/notes
if command -v qmd &>/dev/null; then
  qmd update >> "$LOG" 2>&1 || true
  qmd embed >> "$LOG" 2>&1 || true
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] QMD index updated" >> "$LOG"
fi

# Clean up old lock files
find /tmp -name "claude-*" -mtime +1 -delete 2>/dev/null || true

# Rotate hooks log if > 10MB
HOOKS_LOG="$HOME/vault/logs/hooks.jsonl"
if [ -f "$HOOKS_LOG" ]; then
  SIZE=$(stat -f%z "$HOOKS_LOG" 2>/dev/null || echo "0")
  if [ "$SIZE" -gt 10485760 ]; then
    mv "$HOOKS_LOG" "${HOOKS_LOG}.$(date +%Y%m%d).bak"
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Rotated hooks.jsonl ($SIZE bytes)" >> "$LOG"
  fi
fi

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Daily sync completed" >> "$LOG"
SYNCEOF
chmod +x "$SYNC_SCRIPT"
success "Wrote fallback daily-session-sync.sh (run install.sh for the full export version)"
else
success "daily-session-sync.sh present (install.sh full export version)"
fi

# Create the launchd plist
cat > "$PLIST_FILE" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_NAME</string>

    <key>ProgramArguments</key>
    <array>
        <string>$HOME/vault/scripts/daily-session-sync.sh</string>
    </array>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>9</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>

    <key>StandardOutPath</key>
    <string>$HOME/vault/logs/launchd-sync-stdout.log</string>

    <key>StandardErrorPath</key>
    <string>$HOME/vault/logs/launchd-sync-stderr.log</string>

    <key>RunAtLoad</key>
    <false/>

    <key>Nice</key>
    <integer>10</integer>
</dict>
</plist>
PLISTEOF

success "Created launchd plist: $PLIST_FILE"

# Load the agent (unload first if already loaded, ignore errors)
launchctl unload "$PLIST_FILE" 2>/dev/null || true
launchctl load "$PLIST_FILE" 2>/dev/null || true
success "Launchd agent loaded (runs daily at 09:00)"
action "Created and loaded launchd agent for daily sync"

# ── First-time backfill ──────────────────────────────────────────────────────
# Onboarding must find + index ALL existing sessions NOW, not wait for the 09:00
# cron — the desktop app can rotate ~/.claude/projects/*.jsonl before then, and a
# new user expects /recall to cover their history immediately. Runs the full
# daily-session-sync.sh once (idempotent: skips already-exported sessions).
section "Initial Session Backfill"
if [ -f "$HOME/vault/scripts/onboarding-log.sh" ]; then . "$HOME/vault/scripts/onboarding-log.sh"; else olog(){ :; }; fi
_sess_before=$(find "$HOME/vault/sessions" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ -e "$SYNC_SCRIPT" ]; then
  info "Indexing existing Claude Code / Cowork sessions (this may take a minute)..."
  if bash "$SYNC_SCRIPT"; then
    _sess_after=$(find "$HOME/vault/sessions" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    success "Backfilled existing sessions into the QMD index (+$(( _sess_after - _sess_before )) new)"
    olog backfill 0 sessions_indexed=$(( _sess_after - _sess_before )) sessions_total="$_sess_after"
  else
    warn "Backfill run hit an error — the 09:00 sync will retry"
    olog backfill 1
  fi
else
  warn "daily-session-sync.sh missing — run install.sh, then re-run this script to backfill"
  olog backfill 1 reason=missing-sync-script
fi
olog setup 0

# ============================================================================
# 9. PRINT MANUAL STEPS CHECKLIST
# ============================================================================
section "Manual Steps Required"

echo ""
echo -e "${BOLD}The following steps must be completed manually:${NC}"
echo ""

echo -e "${YELLOW}1. Engine (hooks, warm-start, skills) — via claude-harness/install.sh${NC}"
echo "   The engine is SYMLINKED from one repo, not copied — so a 'git pull' + ./update.sh"
echo "   propagates every fix. If you haven't run it:"
echo "     git clone <claude-harness> ~/code/claude-harness && cd ~/code/claude-harness && ./install.sh"
echo "   That symlinks all hooks + global skills and seeds the vault. Then let Claude drive the rest:"
echo "     open Claude Code → 'Read SETUP_FOR_CLAUDE.md and set up my machine — verify each step.'"
echo ""

echo -e "${YELLOW}3. Open vault-work in Obsidian${NC}"
echo "   Open Obsidian > Open vault > ~/Documents/vault-work/"
echo "   Install required plugins: Bases (built-in), Templater, Calendar"
echo ""

echo -e "${YELLOW}4. Compile VaultRecorder.swift (if using audio capture)${NC}"
echo "   cd ~/Documents/vault-work/System/scripts/VaultRecorder/"
echo "   swiftc VaultRecorder.swift -o VaultRecorder -framework AVFoundation -framework CoreAudio"
echo "   Or build via Xcode."
echo ""

echo -e "${YELLOW}5. Configure CLAUDE.md for Work Projects${NC}"
echo "   Create ~/.claude/CLAUDE.md with your global instructions."
echo "   Create project-specific CLAUDE.md files in each project root."
echo ""

echo -e "${YELLOW}6. Connect MCP servers (optional)${NC}"
echo "   In claude.ai connect account-level MCP (Slack / Linear / PostHog / Drive), then RESTART Claude Code."
echo ""

echo -e "${YELLOW}8. Verify Everything Works${NC}"
echo "   Run: qmd status"
echo "   Run: qmd query 'test' -c sessions"
echo "   Start a Claude Code session and check ~/vault/logs/hooks.jsonl"
echo ""

# ============================================================================
# SUMMARY
# ============================================================================
section "Setup Summary"

echo ""
echo "Actions taken:"
for a in "${ACTIONS[@]}"; do
  echo -e "  ${GREEN}+${NC} $a"
done

echo ""
echo -e "${BOLD}Directory layout:${NC}"
echo "  ~/vault/                     Session vault (transcripts, logs, hooks)"
echo "    sessions/                  Exported session markdown"
echo "    daily/                     Daily journal entries"
echo "    notes/                     Permanent knowledge notes"
echo "    logs/                      Hook execution logs"
echo "    scripts/                   All hook scripts + automation"
echo ""
echo "  ~/Documents/vault-work/      Knowledge vault (Obsidian PM)"
echo "    Daily/                     Daily capture"
echo "    Notes/                     Project notes"
echo "    System/                    Templates, dashboards, scripts"
echo ""
echo "  ~/.claude/                   Claude Code config"
echo "    settings.json              Hooks + permissions + MCP servers"
echo "    scripts/warm-start.sh      Session startup context"
echo "    plans/                     Plan mode outputs"
echo "    skills/                    Custom skills"
echo ""
echo "  ~/.config/qmd/index.yml      QMD search engine config"
echo ""

echo -e "${GREEN}${BOLD}Setup complete.${NC} Review the manual steps above."
