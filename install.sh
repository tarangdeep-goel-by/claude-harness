#!/usr/bin/env bash
# install.sh — deploy the harness onto this machine by symlinking the repo's
# canonical files into ~/.claude and ~/vault/scripts. Idempotent and safe to
# re-run. On a fresh machine: `git clone … && cd claude-harness && ./install.sh`.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Where to seed the vault scaffold (only used if no vault exists there yet).
VAULT_DST="$HOME/Documents/vault-work"
[ "${1:-}" = "--vault" ] && VAULT_DST="${2:?--vault needs a path}"

# Owner vs adopter. Owner mode seeds the full settings.json; adopters get the lighter
# settings.adopter.json. Set HARNESS_OWNER=1 or pass --owner.
if [ "${HARNESS_OWNER:-}" = "1" ] || [ "${1:-}" = "--owner" ]; then OWNER=1; else OWNER=0; fi

# Symlink src → dst, replacing whatever is currently at dst (file, dir, or stale link).
link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ]; then
    [ "$(readlink "$dst")" = "$src" ] && return 0
    rm -f "$dst"
  elif [ -e "$dst" ]; then
    rm -rf "$dst"
  fi
  ln -s "$src" "$dst"
  echo "  linked $dst → ${src/#$HOME/~}"
}

echo "Installing claude-harness from $REPO"

# 1. Data dirs the harness expects to exist (never tracked — machine-local).
mkdir -p \
  ~/.claude/scripts ~/.claude/skills \
  ~/vault/scripts ~/vault/logs/active-sessions \
  ~/vault/sessions ~/vault/daily ~/vault/notes

# 2. Make repo scripts executable.
chmod +x "$REPO"/claude/scripts/*.sh "$REPO"/vault-scripts/*.sh 2>/dev/null || true

# 3. Global Claude config. The harness OWNS settings.json (all hooks live here); personal/machine
#    config belongs in settings.local.json, which Claude Code merges over settings.json and updates
#    never touch. An EXISTING settings.json WITHOUT the harness hooks is the silent-inert trap —
#    the harness loads with no hooks and no error. So take ownership *safely*: back it up, migrate
#    the user's personal keys into settings.local.json, then install the harness copy.
SETTINGS_SRC="$REPO/claude/settings.adopter.json"; [ "$OWNER" = "1" ] && SETTINGS_SRC="$REPO/claude/settings.json"
if [ ! -f "$HOME/.claude/settings.json" ]; then
  cp "$SETTINGS_SRC" "$HOME/.claude/settings.json"
  echo "  settings.json seeded from ${SETTINGS_SRC##*/}"
elif grep -q 'vault/scripts\|warm-start\.sh' "$HOME/.claude/settings.json" 2>/dev/null; then
  echo "  settings.json already has harness hooks — left as-is"
else
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  cp "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.pre-harness-$ts"
  # Preserve personal config as a local override — everything EXCEPT hooks (which come from the harness).
  if command -v jq >/dev/null 2>&1 && [ ! -f "$HOME/.claude/settings.local.json" ]; then
    jq 'del(.hooks)' "$HOME/.claude/settings.json" > "$HOME/.claude/settings.local.json" 2>/dev/null \
      && echo "  migrated your personal settings → settings.local.json (updates never touch it — review it)"
  fi
  cp "$SETTINGS_SRC" "$HOME/.claude/settings.json"
  echo "  ⚠ your settings.json had NO harness hooks (the harness would have been INERT)."
  echo "    backed up → settings.json.pre-harness-$ts; the harness now owns settings.json."
  echo "    put machine-specific config in ~/.claude/settings.local.json; RESTART Claude Code to load hooks."
fi
link "$REPO/claude/scripts/warm-start.sh" "$HOME/.claude/scripts/warm-start.sh"

# 4. Global skills (one symlink per skill dir; coexists with plugin-managed skills).
for s in "$REPO"/claude/skills/*/; do
  name="$(basename "$s")"
  link "${s%/}" "$HOME/.claude/skills/$name"
done

# 4b. Build the QMD skill-retrieval index (powers the skill-retrieval UserPromptSubmit hook).
[ -x "$REPO/vault-scripts/build-skill-index.sh" ] && bash "$REPO/vault-scripts/build-skill-index.sh" 2>/dev/null || true

# 5. Vault hook + automation scripts.
for f in "$REPO"/vault-scripts/*; do
  name="$(basename "$f")"
  link "$f" "$HOME/vault/scripts/$name"
done

# 6. Seed the vault scaffold from vault-template — ONLY if no vault exists (never clobber knowledge).
if [ -d "$VAULT_DST" ] && [ -n "$(ls -A "$VAULT_DST" 2>/dev/null)" ]; then
  echo "  vault present at $VAULT_DST — left untouched (template not applied)."
  echo "    to pull newer skills/templates from the harness, copy selectively from $REPO/vault-template/."
else
  echo "  seeding new vault at $VAULT_DST from vault-template/"
  mkdir -p "$VAULT_DST"
  rsync -a "$REPO/vault-template/" "$VAULT_DST/"
  ( cd "$VAULT_DST" && [ -d .git ] || git init -q 2>/dev/null || true )
  echo "  ✓ vault seeded — open it in Obsidian, then fill Meta/memory.md via /onboard."
fi

echo ""
echo "✓ Harness + vault scaffold installed.  Next (in order):"
echo "  1) ./bootstrap.sh                                         deps: jq, qmd, gh, python3"
echo "  2) bash \"$VAULT_DST/System/scripts/setup-work-machine.sh\"   qmd index, transcription models, launchd"
echo "  3) copy secrets → ~/.claude + ~/code/.env                 (see SECRETS.md)"
echo "  4) connect MCP (Slack/Linear/PostHog) in claude.ai, then RESTART Claude Code"
echo "  5) ./verify-setup.sh                                      confirm everything's wired"
echo "  6) open $VAULT_DST in Obsidian → run /onboard to fill Meta/memory.md"

# onboarding telemetry (no-op if helper missing)
if [ -f "$REPO/vault-scripts/onboarding-log.sh" ]; then . "$REPO/vault-scripts/onboarding-log.sh"; olog install 0; fi
