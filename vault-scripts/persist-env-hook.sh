#!/bin/bash
# SessionStart hook: persist Docker & environment variables for the session.
# Writes to $CLAUDE_ENV_FILE so all subsequent Bash calls inherit the env.
set -euo pipefail

HOOKS_LOG="$HOME/vault/logs/hooks.jsonl"
mkdir -p "$(dirname "$HOOKS_LOG")"

# CLAUDE_ENV_FILE is set by Claude Code — if missing, nothing to do
if [ -z "${CLAUDE_ENV_FILE:-}" ]; then
  printf '{"ts":"%s","hook":"persist-env","outcome":"skip","detail":"no CLAUDE_ENV_FILE"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$HOOKS_LOG"
  exit 0
fi

# Read hook input for cwd
INPUT=""
if [ ! -t 0 ]; then
  INPUT=$(cat)
fi

CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || pwd)

# ── Data tool credentials ────────────────────────────────────────────────
DATA_TOOLS_ENV="$HOME/.claude/.env.data-tools"
if [ -f "$DATA_TOOLS_ENV" ]; then
  # Source and re-export to CLAUDE_ENV_FILE so all Bash calls (including subagents) inherit
  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    # Only export lines that have a non-empty value (skip placeholder lines with ="")
    if [[ "$line" =~ ^export\ ([A-Z_]+)=\"(.+)\"$ ]]; then
      echo "$line" >> "$CLAUDE_ENV_FILE"
    fi
  done < "$DATA_TOOLS_ENV"
fi

# ── Docker defaults ──────────────────────────────────────────────────────
echo 'export DOCKER_BUILDKIT=1' >> "$CLAUDE_ENV_FILE"
echo 'export COMPOSE_DOCKER_CLI_BUILD=1' >> "$CLAUDE_ENV_FILE"

# Apple Silicon: default platform
if [ "$(uname -m)" = "arm64" ]; then
  echo 'export DOCKER_DEFAULT_PLATFORM=linux/arm64' >> "$CLAUDE_ENV_FILE"
fi

# ── Detect compose file & project name ───────────────────────────────────
COMPOSE_FILE=""
for candidate in "$CWD/docker-compose.yml" "$CWD/docker-compose.yaml" "$CWD/compose.yml" "$CWD/compose.yaml"; do
  if [ -f "$candidate" ]; then
    COMPOSE_FILE="$candidate"
    break
  fi
done

# Worktree compose override — check for docker-compose.worktree.yml
if [ -f "$CWD/docker-compose.worktree.yml" ]; then
  echo "export COMPOSE_FILE=\"$COMPOSE_FILE:$CWD/docker-compose.worktree.yml\"" >> "$CLAUDE_ENV_FILE"
fi

# Derive COMPOSE_PROJECT_NAME from directory name (matches Docker default)
if [ -n "$COMPOSE_FILE" ]; then
  PROJECT_NAME=$(basename "$CWD" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]//g')
  echo "export COMPOSE_PROJECT_NAME=\"$PROJECT_NAME\"" >> "$CLAUDE_ENV_FILE"
fi

# ── Detect running containers for this project ──────────────────────────
if command -v docker &>/dev/null; then
  RUNNING=$(docker ps --filter "label=com.docker.compose.project" --format '{{.Names}}: {{.Ports}}' 2>/dev/null | head -10 || true)
  if [ -n "$RUNNING" ]; then
    # Expose as a readable env var so Claude knows what's running
    ESCAPED=$(echo "$RUNNING" | tr '\n' '|')
    echo "export DOCKER_RUNNING_CONTAINERS=\"$ESCAPED\"" >> "$CLAUDE_ENV_FILE"
  fi
fi

# ── Project .env passthrough ─────────────────────────────────────────────
# If the project has a .env, make docker compose aware of it
if [ -f "$CWD/.env" ]; then
  echo "export COMPOSE_ENV_FILE=\"$CWD/.env\"" >> "$CLAUDE_ENV_FILE"
fi

# ── PATH: add common tools ──────────────────────────────────────────────
for bindir in "$HOME/.local/bin" "$CWD/node_modules/.bin" "$CWD/scripts"; do
  if [ -d "$bindir" ]; then
    echo "export PATH=\"$bindir:\$PATH\"" >> "$CLAUDE_ENV_FILE"
  fi
done

# Homebrew (macOS)
if [ -f "/opt/homebrew/bin/brew" ] && ! echo "$PATH" | grep -q "/opt/homebrew/bin"; then
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$CLAUDE_ENV_FILE"
fi

printf '{"ts":"%s","hook":"persist-env","outcome":"ok","detail":"docker env written"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$HOOKS_LOG"
