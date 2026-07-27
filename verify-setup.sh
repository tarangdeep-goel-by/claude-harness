#!/usr/bin/env bash
# verify-setup.sh — post-install health check. Flags anything that would make the harness silently
# degrade (broken symlink, missing qmd, empty memory, absent creds). Read-only; warns, never fails.
# Run after: install.sh → bootstrap.sh → copy secrets → /onboard.
#   Usage:  ./verify-setup.sh [--vault <path>]
set -uo pipefail
VAULT_DST="$HOME/Documents/vault-work"; JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json)  JSON=1 ;;
    --vault) VAULT_DST="${2:?}"; shift ;;
    *) ;;
  esac
  shift
done
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_FILE="$(mktemp "${TMPDIR:-/tmp}/verify.XXXXXX")"; trap 'rm -f "$RESULTS_FILE"' EXIT
# ok/warn record every check (for --json) and print human output unless in JSON mode.
ok(){   printf 'ok\t%s\n'   "$1" >>"$RESULTS_FILE"; [ "$JSON" = 1 ] || printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn(){ printf 'warn\t%s\n' "$1" >>"$RESULTS_FILE"; [ "$JSON" = 1 ] || printf '  \033[33m⚠\033[0m %s\n' "$1"; }
hdr(){  [ "$JSON" = 1 ] || echo "$1"; }
hdr "== claude-harness setup check =="

hdr "engine (symlinks):"
# install.sh COPIES settings.json (owner and adopter variants differ per machine — it can't be a
# shared symlink), so check presence, not symlink-ness.
[ -e "$HOME/.claude/settings.json" ] && ok "settings.json present" || warn "settings.json missing — re-run ./install.sh"
[ -e "$HOME/.claude/scripts/warm-start.sh" ] && ok "warm-start linked" || warn "warm-start.sh missing — re-run ./install.sh"
# Every harness skill must be SYMLINKED into ~/.claude/skills — a local copy silently drifts from
# the harness (the failure mode that forked infra-health + vault-audit). Verify, don't just count.
# SM-coupled skills are intentionally NOT linked for adopters (install.sh skips them), so a missing
# one is expected there — only flag it as missing in owner mode.
OWNER="${HARNESS_OWNER:-0}"
SM_COUPLED_SKILLS="analysis capture-journey-generic"
sk_linked=0 sk_local=0 sk_missing=0 sk_skipped=0
for sd in "$REPO"/claude/skills/*/; do
  [ -d "$sd" ] || continue
  sk=$(basename "$sd"); dst="$HOME/.claude/skills/$sk"
  if [ -L "$dst" ]; then sk_linked=$((sk_linked+1))
  elif [ -e "$dst" ]; then sk_local=$((sk_local+1)); warn "skill '$sk' is a LOCAL COPY, not a symlink → drifts from the harness; re-run ./install.sh"
  else
    case " $SM_COUPLED_SKILLS " in
      *" $sk "*) if [ "$OWNER" = "1" ]; then sk_missing=$((sk_missing+1)); warn "skill '$sk' not linked (owner mode expects it) — re-run ./install.sh"; else sk_skipped=$((sk_skipped+1)); fi ;;
      *) sk_missing=$((sk_missing+1)); warn "skill '$sk' not linked into ~/.claude/skills — re-run ./install.sh" ;;
    esac
  fi
done
if [ "$sk_local" = 0 ] && [ "$sk_missing" = 0 ]; then
  msg="$sk_linked harness skills symlinked (single-sourced)"
  [ "$sk_skipped" -gt 0 ] && msg="$msg · $sk_skipped SM-coupled skipped (adopter)"
  ok "$msg"
else warn "skills: $sk_linked symlinked · $sk_local local-copies · $sk_missing missing — ./install.sh re-symlinks"; fi
[ -d "$HOME/vault/scripts" ] && ok "~/vault/scripts present" || warn "~/vault/scripts missing — re-run ./install.sh"

hdr "dependencies:"
command -v jq >/dev/null && ok "jq" || warn "jq missing (warm-start needs it)"
command -v python3 >/dev/null && ok "python3" || warn "python3 missing (hooks need it)"
if command -v qmd >/dev/null; then
  qmd status >/dev/null 2>&1 && ok "qmd (index reachable)" || warn "qmd present but index not built — run: qmd update && qmd embed"
else
  warn "qmd MISSING — /recall + warm-start context + session search will not work."
  warn "  Install: npm install -g @tobilu/qmd   (or: bun install -g @tobilu/qmd)   — source: github.com/tobi/qmd"
  warn "  Needs Node >=22 or Bun; on macOS also: brew install sqlite. First use downloads ~2GB of models to ~/.cache/qmd."
  warn "  After installing: qmd update && qmd embed  (to build the index)"
  warn "  Without qmd, warm-start degrades gracefully but recall is fully disabled."
fi
command -v gh >/dev/null && ok "gh" || warn "gh missing (/dev-task needs it)"

hdr "codex (optional):"
[ -e "$HOME/.codex/hooks.json" ] && ok "Codex hooks.json present" || warn "~/.codex/hooks.json missing — run ./install-codex.sh if you use Codex"
[ -e "$HOME/.codex/scripts/codex_hook_adapter.py" ] && ok "Codex hook adapter present" || warn "~/.codex/scripts/codex_hook_adapter.py missing — run ./install-codex.sh if you use Codex"

hdr "vault + knowledge:"
[ -d "$VAULT_DST" ] && ok "vault at $VAULT_DST" || warn "no vault at $VAULT_DST — run ./install.sh"
if [ -f "$VAULT_DST/Meta/memory.md" ]; then
  grep -qi 'fill via /onboard\|onboarding context' "$VAULT_DST/Meta/memory.md" \
    && warn "Meta/memory.md is still the template — run /onboard to populate it" \
    || ok "Meta/memory.md populated"
else
  warn "Meta/memory.md missing"
fi

hdr "data layer:"
[ -f "$HOME/code/.env" ] && ok "~/code/.env present" || warn "~/code/.env missing — add your data-stack credentials here (see SECRETS.example.md)"
# Add your own data library check here, e.g.:
# [ -d "$HOME/code/my-analytics/.venv" ] && ok "analytics venv" || warn "analytics venv missing"

if [ "$JSON" = 1 ]; then
  INSTALL_ID="$(tr -d '[:space:]' < "$HOME/.claude/harness-install-id" 2>/dev/null || echo unknown)"
  VER="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  OPERATOR="$(git config --global user.email 2>/dev/null || true)"
  [ -z "$OPERATOR" ] && OPERATOR="${USER:-unknown}"
  python3 - "$RESULTS_FILE" "$INSTALL_ID" "$VER" "$(uname -s 2>/dev/null || echo unknown)" "$OWNER" "$OPERATOR" "$HOME/vault/logs/onboarding.jsonl" <<'PY'
import sys, json, os as _os
rf, iid, ver, os_, owner, operator, olog_path = sys.argv[1:8]
checks=[]
for ln in open(rf):
    st,_,msg=ln.rstrip("\n").partition("\t")
    if st: checks.append({"status":st,"check":msg})
warns=sum(1 for c in checks if c["status"]=="warn")
steps=[]
if _os.path.exists(olog_path):
    for l in open(olog_path):
        l=l.strip()
        if l:
            try: steps.append(json.loads(l))
            except Exception: pass
print(json.dumps({"kind":"onboarding","operator":operator,"install_id":iid,"harness_version":ver,"os":os_,
  "mode":"owner" if owner=="1" else "adopter",
  "ok":sum(1 for c in checks if c["status"]=="ok"),"warn":warns,
  "healthy":warns==0,"checks":checks,"onboarding_steps":steps[-10:]}))
PY
else
  echo ""
  echo "⚠ = finish before the harness is fully live. None of these block opening Claude Code."
  echo "Reminder: connect account-level MCP (Slack/Linear/PostHog) in claude.ai, then RESTART Claude Code."
fi

# onboarding telemetry: record the verify outcome (no-op if helper missing)
if [ -f "$HOME/vault/scripts/onboarding-log.sh" ]; then . "$HOME/vault/scripts/onboarding-log.sh"; else olog(){ :; }; fi
_vw=$(grep -c '^warn' "$RESULTS_FILE" 2>/dev/null || echo 0)
olog verify "$([ "${_vw:-0}" -eq 0 ] && echo 0 || echo 1)" warnings="${_vw:-0}"
