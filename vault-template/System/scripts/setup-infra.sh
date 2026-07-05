#!/usr/bin/env bash
# ============================================================================
# setup-infra.sh — Bootstrap PM vault infrastructure on a new Mac
# ============================================================================
#
# Run this once on your work machine after copying vault-work/:
#   cd vault-work && bash System/scripts/setup-infra.sh
#
# What it sets up:
#   1. Homebrew packages (whisper-cpp, ffmpeg, tmux, etc.)
#   2. Whisper + VAD models
#   3. QMD (vault search engine)
#   4. Claude Code skills (recall, vault-push, dev-task, infra-health, etc. — symlinked by claude-harness/install.sh)
#   5. Claude Code hooks (warm-start, session export, safety guards, etc.)
#   6. Claude Code settings (MCP servers, permissions, hooks config)
#   7. VaultRecorder (menu bar audio recorder)

set -euo pipefail

VAULT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CLAUDE_DIR="$HOME/.claude"
VAULT_SCRIPTS="$VAULT_DIR/System/scripts"

echo "============================================"
echo "  PM Vault Infrastructure Setup"
echo "  Vault: $VAULT_DIR"
echo "============================================"
echo ""

# ── 1. Homebrew packages ─────────────────────────────────────────────────

echo "==> [1/7] Homebrew packages"

if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

PACKAGES=(
  # Core vault infrastructure
  whisper-cpp     # Local transcription
  ffmpeg          # Audio conversion
  tmux            # Long-running processes
  gh              # GitHub CLI
  jq              # JSON processing
  pandoc          # MD → DOCX conversion
  # CLI productivity
  bat             # Better cat — syntax highlighted file viewing
  eza             # Better ls — tree view with icons
  fd              # Better find — fast file search
  fzf             # Fuzzy finder — interactive search
  ripgrep         # Better grep — fastest text search
  zoxide          # Better cd — jump to frequent dirs ('z vault-work')
  mermaid-cli     # Render Mermaid diagrams to PNG/SVG
)

for pkg in "${PACKAGES[@]}"; do
  if brew list "$pkg" &>/dev/null; then
    echo "  ✓ $pkg (installed)"
  else
    echo "  Installing $pkg..."
    brew install "$pkg"
  fi
done

# Desktop apps (casks)
CASKS=(
  arc                 # Browser
  obsidian            # Vault / second brain
  figma               # Design reviews
  rectangle           # Window management
  maccy               # Clipboard manager
  visual-studio-code  # Code reading
  drawio              # Architecture diagrams
)

for cask in "${CASKS[@]}"; do
  if brew list --cask "$cask" &>/dev/null; then
    echo "  ✓ $cask (installed)"
  else
    echo "  Installing $cask..."
    brew install --cask "$cask"
  fi
done

echo ""

# Python tools (via pipx for isolation)
if ! command -v pipx &>/dev/null; then
  echo "  Installing pipx..."
  brew install pipx
  pipx ensurepath
fi

if command -v markitdown &>/dev/null; then
  echo "  ✓ markitdown (installed)"
else
  echo "  Installing markitdown (document → markdown converter)..."
  pipx install 'markitdown[all]' 2>/dev/null || \
    echo "  ⚠ markitdown install failed — run: pipx install 'markitdown[all]'"
fi

if command -v nlm &>/dev/null; then
  echo "  ✓ nlm (NotebookLM CLI installed)"
else
  echo "  Installing notebooklm-mcp-cli (NotebookLM CLI + MCP)..."
  pipx install notebooklm-mcp-cli 2>/dev/null || \
    echo "  ⚠ nlm install failed — run: pipx install notebooklm-mcp-cli"
fi

# BlackHole for system audio capture (requires sudo)
if ! brew list --cask blackhole-2ch &>/dev/null; then
  echo ""
  echo "  BlackHole (system audio capture) requires sudo."
  echo "  Run manually: brew install --cask blackhole-2ch"
  echo ""
fi

echo ""

# ── 2. Whisper + VAD models ──────────────────────────────────────────────

echo "==> [2/7] Whisper + VAD models"

MODEL_DIR="$HOME/.local/share/whisper-models"
mkdir -p "$MODEL_DIR"

WHISPER_MODEL="$MODEL_DIR/ggml-large-v3-turbo.bin"
VAD_MODEL="$MODEL_DIR/ggml-silero-v6.2.0.bin"

if [ -f "$WHISPER_MODEL" ]; then
  echo "  ✓ Whisper large-v3-turbo (exists)"
else
  echo "  Downloading Whisper large-v3-turbo (~1.6GB)..."
  curl -L -o "$WHISPER_MODEL" \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"
fi

if [ -f "$VAD_MODEL" ]; then
  echo "  ✓ Silero VAD v6.2.0 (exists)"
else
  echo "  Downloading Silero VAD v6.2.0..."
  curl -L -o "$VAD_MODEL" \
    "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin"
fi

echo ""

# ── 3. QMD ───────────────────────────────────────────────────────────────

echo "==> [3/7] QMD (vault search engine)"

if command -v qmd &>/dev/null; then
  echo "  ✓ QMD (installed)"
else
  echo "  QMD not found. Install it manually:"
  echo "    See: qmd query 'qmd-vault-infrastructure' -c notes"
  echo "  Or install from your personal machine's QMD source."
  echo ""
fi

echo ""

# ── 4. Claude Code skills ────────────────────────────────────────────────

echo "==> [4/7] Claude Code skills"

SKILLS_DIR="$CLAUDE_DIR/skills"
mkdir -p "$SKILLS_DIR"

# Skills to port (non-dev, PM-relevant)
SKILLS_TO_PORT=(
  recall
  vault-push
  vault-audit
  stats
  find-skills
  warm
)

SOURCE_SKILLS="$VAULT_DIR/System/portable-skills"

for skill in "${SKILLS_TO_PORT[@]}"; do
  if [ -d "$SOURCE_SKILLS/$skill" ]; then
    if [ -d "$SKILLS_DIR/$skill" ]; then
      echo "  ✓ $skill (exists)"
    else
      cp -r "$SOURCE_SKILLS/$skill" "$SKILLS_DIR/$skill"
      echo "  Installed: $skill"
    fi
  else
    echo "  ⚠ $skill (not found in vault — check System/portable-skills/)"
  fi
done

echo ""

# ── 5. Claude Code hooks ────────────────────────────────────────────────

echo "==> [5/7] Claude Code hooks"

HOOKS_DIR="$HOME/vault/scripts"
mkdir -p "$HOOKS_DIR"
mkdir -p "$HOME/vault/logs"
mkdir -p "$HOME/vault/sessions"
mkdir -p "$CLAUDE_DIR/scripts"

SOURCE_HOOKS="$VAULT_DIR/System/portable-hooks"

# Copy all hook scripts from vault bundle
for hook_file in "$SOURCE_HOOKS"/*.sh "$SOURCE_HOOKS"/*.py; do
  [ -f "$hook_file" ] || continue
  name=$(basename "$hook_file")

  # warm-start goes to ~/.claude/scripts/, everything else to ~/vault/scripts/
  if [ "$name" = "warm-start.sh" ]; then
    dst="$CLAUDE_DIR/scripts/$name"
  else
    dst="$HOOKS_DIR/$name"
  fi

  if [ -f "$dst" ]; then
    echo "  ✓ $name (exists)"
  else
    cp "$hook_file" "$dst"
    chmod +x "$dst"
    echo "  Installed: $name"
  fi
done

echo ""

# ── 6. Claude Code settings ─────────────────────────────────────────────

echo "==> [6/7] Claude Code settings"

SETTINGS_FILE="$CLAUDE_DIR/settings.json"

if [ -f "$SETTINGS_FILE" ]; then
  echo "  Settings file exists. Review and update manually if needed."
  echo "  Key items to verify:"
  echo "    - hooks paths point to correct locations"
  echo "    - MCP servers (tmux, gemini-bridge) are configured"
  echo "    - permissions are set"
else
  echo "  Creating settings.json..."
  cat > "$SETTINGS_FILE" << 'SETTINGS_EOF'
{
  "permissions": {
    "allow": [
      "Write",
      "Edit",
      "Bash"
    ]
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
    "PostToolUse": [],
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
  "mcpServers": {
    "tmux": {
      "command": "npx",
      "args": ["-y", "tmux-mcp", "--shell-type=zsh"]
    },
    "gemini-bridge": {
      "command": "VAULT_DIR/System/mcp/gemini-bridge/.venv/bin/python",
      "args": ["VAULT_DIR/System/mcp/gemini-bridge/server.py"],
      "env": {
        "GEMINI_API_KEY": "YOUR_GEMINI_API_KEY_HERE"
      }
    }
  },
  "syntaxHighlightingDisabled": false,
  "alwaysThinkingEnabled": true,
  "effortLevel": "high"
}
SETTINGS_EOF
  echo "  Created settings.json"
fi

echo ""

# ── 7. Gemini Bridge MCP ────────────────────────────────────────────────

echo "==> [7/8] Gemini Bridge MCP"

GEMINI_DIR="$VAULT_DIR/System/mcp/gemini-bridge"

if [ -f "$GEMINI_DIR/server.py" ]; then
  if [ -d "$GEMINI_DIR/.venv" ]; then
    echo "  ✓ Gemini bridge venv (exists)"
  else
    echo "  Setting up Gemini bridge venv..."
    python3 -m venv "$GEMINI_DIR/.venv"
    "$GEMINI_DIR/.venv/bin/pip" install -q -r "$GEMINI_DIR/requirements.txt"
    echo "  ✓ Gemini bridge ready"
  fi
  echo "  ⚠ Remember to set GEMINI_API_KEY in ~/.claude/settings.json"
else
  echo "  ⚠ Gemini bridge not found at $GEMINI_DIR"
fi

echo ""

# ── 8. VaultRecorder ────────────────────────────────────────────────────

echo "==> [8/8] VaultRecorder (menu bar recorder)"

RECORDER="$VAULT_SCRIPTS/VaultRecorder"

if [ -f "$RECORDER" ]; then
  echo "  ✓ VaultRecorder binary (exists)"
else
  SWIFT_SRC="$VAULT_SCRIPTS/VaultRecorder.swift"
  if [ -f "$SWIFT_SRC" ]; then
    echo "  Compiling VaultRecorder..."
    swiftc "$SWIFT_SRC" -o "$RECORDER" -framework Cocoa -framework AVFoundation 2>/dev/null && \
      echo "  ✓ Compiled VaultRecorder" || \
      echo "  ⚠ Compilation failed — compile manually: swiftc VaultRecorder.swift -o VaultRecorder -framework Cocoa -framework AVFoundation"
  else
    echo "  ⚠ VaultRecorder.swift not found"
  fi
fi

echo ""

# ── Done ─────────────────────────────────────────────────────────────────

echo "============================================"
echo "  Setup complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Open Obsidian → Open folder as vault → select vault-work/"
echo "  2. Run: cd $VAULT_DIR && claude"
echo "  3. Run: /onboard (fill in memory file)"
echo "  4. Run: /resume (start your first session)"
echo ""
echo "Optional:"
echo "  - brew install --cask blackhole-2ch  (system audio capture, needs sudo)"
echo "  - bash System/scripts/setup_gdrive.sh  (Google Drive uploads)"
echo "  - Set up QMD collections pointing at vault-work/"
echo ""
