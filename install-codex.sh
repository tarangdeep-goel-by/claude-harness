#!/usr/bin/env bash
# install-codex.sh - install Codex hook support without touching Claude setup.
# Idempotent and safe to re-run.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_SRC="$REPO/codex"
CODEX_HOME="$HOME/.codex"
TS="$(date -u +%Y%m%dT%H%M%SZ)"

backup_path() {
  local dst="$1"
  printf '%s.backup-%s' "$dst" "$TS"
}

backup_existing() {
  local dst="$1" backup
  backup="$(backup_path "$dst")"
  while [ -e "$backup" ] || [ -L "$backup" ]; do
    backup="$backup.$$"
  done

  if [ -L "$dst" ]; then
    cp -P "$dst" "$backup"
    rm -f "$dst"
  else
    mv "$dst" "$backup"
  fi
  echo "  backed up ${dst/#$HOME/~} -> ${backup/#$HOME/~}"
}

link_script() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"

  if [ -L "$dst" ]; then
    if [ "$(readlink "$dst")" = "$src" ]; then
      echo "  linked ${dst/#$HOME/~} (already current)"
      return 0
    fi
    rm -f "$dst"
  elif [ -e "$dst" ]; then
    backup_existing "$dst"
  fi

  ln -s "$src" "$dst"
  echo "  linked ${dst/#$HOME/~} -> ${src/#$HOME/~}"
}

install_hooks_json() {
  local src="$CODEX_SRC/hooks.json" dst="$CODEX_HOME/hooks.json" backup rendered
  if [ ! -f "$src" ]; then
    echo "missing required source: ${src/#$REPO/}" >&2
    exit 1
  fi
  rendered="$(mktemp "${TMPDIR:-/tmp}/codex-hooks.XXXXXX.json")"
  python3 - "$src" "$rendered" "$CODEX_HOME" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
codex_home = sys.argv[3]


def rewrite(value):
    if isinstance(value, str):
        return value.replace("~/.codex", codex_home)
    if isinstance(value, list):
        return [rewrite(item) for item in value]
    if isinstance(value, dict):
        return {key: rewrite(item) for key, item in value.items()}
    return value


data = rewrite(json.loads(src.read_text()))
dst.write_text(json.dumps(data, indent=2) + "\n")
PY

  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if cmp -s "$rendered" "$dst"; then
      echo "  hooks.json already current"
      rm -f "$rendered"
      return 0
    fi
    backup="$(backup_path "$dst")"
    while [ -e "$backup" ] || [ -L "$backup" ]; do
      backup="$backup.$$"
    done
    if [ -L "$dst" ]; then
      cp -P "$dst" "$backup"
      rm -f "$dst"
    else
      cp -p "$dst" "$backup"
    fi
    echo "  backed up ${dst/#$HOME/~} -> ${backup/#$HOME/~}"
  fi

  cp "$rendered" "$dst"
  rm -f "$rendered"
  echo "  installed ${dst/#$HOME/~}"
}

if [ ! -d "$CODEX_SRC/scripts" ]; then
  echo "missing required source directory: ${CODEX_SRC/#$REPO/}/scripts" >&2
  exit 1
fi

echo "Installing Codex harness support from $REPO"

mkdir -p \
  "$CODEX_HOME/scripts" \
  "$HOME/vault/sessions" \
  "$HOME/vault/logs"

for f in "$CODEX_SRC"/scripts/*; do
  [ -f "$f" ] || continue
  link_script "$f" "$CODEX_HOME/scripts/$(basename "$f")"
done

install_hooks_json

echo ""
echo "config.toml was not overwritten."
echo "  Merge Codex features, MCP, and plugin config manually from:"
echo "  ${CODEX_SRC/#$REPO/}/config.example.toml"

echo ""
echo "Next steps:"
echo "  1. Verify codex_hooks=true in your Codex config."
echo "  2. Run: python3 ~/.codex/scripts/codex_hooks_doctor.py"
echo "  3. Once QMD is fixed, run: qmd status"
