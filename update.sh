#!/usr/bin/env bash
# update.sh — pull the latest harness and reconcile this machine CLEANLY. Idempotent.
# Fixes what a bare `git pull` leaves stale:
#   • new skills/scripts unlinked        → (re)symlink them
#   • removed/renamed skills dangling     → prune stale symlinks
#   • settings.json never refreshed       → re-apply (machine-specifics live in settings.local.json)
#   • vault infra (System/scripts,        → rsync (content is left alone; new default daily-jobs
#     templates) not propagated             are reported, never force-merged)
# Finally emits an onboarding/update report to the shared telemetry sink (opt-in) so the
# maintainer can see whether the update landed cleanly on this machine.
#
# Usage:  ./update.sh [--owner] [--no-pull] [--vault <path>]
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DST="$HOME/Documents/vault-work"; OWNER="${HARNESS_OWNER:-0}"; PULL=1
while [ $# -gt 0 ]; do
  case "$1" in
    --owner)   OWNER=1 ;;
    --no-pull) PULL=0 ;;
    --vault)   VAULT_DST="${2:?}"; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done
SM_COUPLED_SKILLS="analysis capture-journey-generic"

link() {  # src → dst, replacing file/dir/stale-link
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ]; then [ "$(readlink "$dst")" = "$src" ] && return 0; rm -f "$dst"
  elif [ -e "$dst" ]; then rm -rf "$dst"; fi
  ln -s "$src" "$dst"
}
is_sm_coupled() { case " $SM_COUPLED_SKILLS " in *" $1 "*) return 0;; *) return 1;; esac; }

echo "== claude-harness update =="

# 0. Pull — only with a clean tree, never clobber local work.
before="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '?')"
if [ "$PULL" = 1 ]; then
  if git -C "$REPO" diff --quiet 2>/dev/null && git -C "$REPO" diff --cached --quiet 2>/dev/null; then
    git -C "$REPO" pull --ff-only 2>&1 | sed 's/^/  /' || echo "  ⚠ pull not fast-forward — resolve manually, then re-run"
  else
    echo "  ⚠ repo has uncommitted changes — skipping pull (commit/stash for a clean update)"
  fi
fi
after="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '?')"
echo "  harness: $before → $after"

# 1. Skills — (re)link current, skip SM-coupled for adopters, PRUNE stale.
linked=0 pruned=0
for s in "$REPO"/claude/skills/*/; do
  [ -d "$s" ] || continue
  name="$(basename "$s")"
  if is_sm_coupled "$name" && [ "$OWNER" != 1 ]; then continue; fi
  link "${s%/}" "$HOME/.claude/skills/$name"; linked=$((linked+1))
done
for d in "$HOME"/.claude/skills/*; do
  [ -L "$d" ] || continue
  tgt="$(readlink "$d")"; base="$(basename "$d")"
  case "$tgt" in
    "$REPO"/claude/skills/*)
      # target gone (removed skill) OR SM-coupled in adopter mode → prune
      if [ ! -e "$tgt" ] || { is_sm_coupled "$base" && [ "$OWNER" != 1 ]; }; then
        rm -f "$d"; echo "  pruned skill symlink: $base"; pruned=$((pruned+1))
      fi ;;
  esac
done
link "$REPO/claude/scripts/warm-start.sh" "$HOME/.claude/scripts/warm-start.sh"
echo "  skills: $linked linked · $pruned pruned"

# 2. Vault hook/automation scripts — relink current, prune stale.
for f in "$REPO"/vault-scripts/*; do link "$f" "$HOME/vault/scripts/$(basename "$f")"; done
for d in "$HOME"/vault/scripts/*; do
  [ -L "$d" ] || continue; tgt="$(readlink "$d")"
  case "$tgt" in "$REPO"/vault-scripts/*) [ -e "$tgt" ] || { rm -f "$d"; echo "  pruned vault-script: $(basename "$d")"; };; esac
done

# 3. settings.json — harness-managed; refresh if it drifted (back up first). Put machine-specific
#    overrides in settings.local.json (Claude Code merges it) so updates never clobber them.
src="settings.adopter.json"; [ "$OWNER" = 1 ] && src="settings.json"
if [ -f "$REPO/claude/$src" ] && ! diff -q "$REPO/claude/$src" "$HOME/.claude/settings.json" >/dev/null 2>&1; then
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  [ -f "$HOME/.claude/settings.json" ] && cp "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.bak-$ts"
  cp "$REPO/claude/$src" "$HOME/.claude/settings.json"
  echo "  settings.json refreshed (backup: settings.json.bak-$ts) — RESTART Claude Code to reload hooks"
else
  echo "  settings.json up to date"
fi

# 4. Vault infra — update scripts/templates (safe infra); never touch notes/config. Report new
#    default daily-jobs rather than force-merging the adopter's daily-jobs.yaml.
if [ -d "$VAULT_DST" ]; then
  rsync -a "$REPO/vault-template/System/scripts/"   "$VAULT_DST/System/scripts/"   2>/dev/null || true
  rsync -a "$REPO/vault-template/System/templates/" "$VAULT_DST/System/templates/" 2>/dev/null || true
  tj="$REPO/vault-template/System/daily-jobs.yaml"; aj="$VAULT_DST/System/daily-jobs.yaml"
  if [ -f "$tj" ] && [ -f "$aj" ]; then
    while IFS= read -r jn; do
      grep -q "name: *$jn" "$aj" || echo "  ℹ new default daily-job available: '$jn' — add it to $aj (not force-merged)"
    done < <(grep -oE 'name: *[A-Za-z0-9_-]+' "$tj" | sed 's/name: *//')
  fi
fi

# 5. Onboarding/update report → telemetry sink (opt-in; no-op if unconfigured).
if [ -x "$REPO/verify-setup.sh" ] && [ -x "$HOME/.claude/skills/infra-health/scripts/collect_telemetry.sh" ]; then
  rpt="$(mktemp "${TMPDIR:-/tmp}/onboard.XXXXXX.json")"
  HARNESS_OWNER="$OWNER" "$REPO/verify-setup.sh" --json --vault "$VAULT_DST" > "$rpt" 2>/dev/null || true
  bash "$HOME/.claude/skills/infra-health/scripts/collect_telemetry.sh" --onboarding "$rpt" --if-configured 2>/dev/null \
    && echo "  onboarding report sent to telemetry sink (if configured)" || true
  rm -f "$rpt"
fi

echo "✓ update complete."
