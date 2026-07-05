#!/usr/bin/env bash
# make-vault-template.sh — (re)generate this repo's vault-template/ from a live vault, stripped of
# all knowledge. This is how claude-harness stays a COMPLETE, shareable harness: the vault-template
# is the project half (skills + templates + structure + conventions) that install.sh seeds for a
# new user. Run this after you evolve your skills/templates/CLAUDE.md, then commit vault-template/.
#
# Allowlist by design — only structural/template/skill files are copied; notes, daily captures,
# memory facts, sessions, handoffs, People/Glossary content, secrets and caches are NEVER touched.
#
# Usage:  ./make-vault-template.sh [SOURCE_VAULT]   (default ~/Documents/vault-work)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${1:-$HOME/Documents/vault-work}"
VT="$REPO/vault-template"
[ -d "$SRC/.claude" ] || { echo "no vault at $SRC"; exit 1; }
say(){ printf '  %s\n' "$*"; }

# Skills to EXCLUDE from the shareable cross-org template.
# KEEP: recall, vault-push, vault-audit, stats, infra-health, humanizer, drawio,
#       karpathy-guidelines, find-skills, reflect, transcriber, dev-task, update-config,
#       scribe, sorter, compiler (generic capture/continuity).
# STRIP: all company-data and product-domain skills — they encode Stable Money's specific
#        data stack (Mixpanel project IDs, Metabase DB schemas, product funnels, referral
#        business logic) and are not meaningful to an outside adopter.
DOMAIN_SKILLS="analysis metabase-query metabase-instrumentation mixpanel-analytics mixpanel-instrumentation mixpanel-chart-builder referral-investigation referral-forensics capture-journey capture-journey-generic play-console flutter-dev sm-design-system"

echo "Regenerating $VT from $SRC (knowledge-stripped)"
rm -rf "$VT"; mkdir -p "$VT"

# --- capability layer: skills (minus domain), agents, commands ---
rsync -aq "$SRC/.claude/" "$VT/.claude/" --exclude='settings.local.json' --exclude='.DS_Store' --exclude='worktrees'
for d in $DOMAIN_SKILLS; do rm -rf "$VT/.claude/skills/$d"; done
say ".claude/ skills (domain skills [$DOMAIN_SKILLS] + settings.local excluded), agents, commands"

# --- operating manual (annotated to adapt) ---
{ cat <<'BANNER'; cat "$SRC/CLAUDE.md"; } > "$VT/CLAUDE.md"
> **TEMPLATE — adapt before use** (shareable scaffold from `claude-harness`).
> Keep the architecture, routing, cadence, and conventions below — they're the reusable core.
> Change only what's yours:
> - [ ] Your product area / scope — this was written around the author's area, not yours.
> - [ ] Run `/onboard` to fill `Meta/memory.md` (who you are, team, scope).
> - [ ] **Already used Claude Code here?** Don't start empty — run `./catalog-sessions.sh 30` in the
>       harness repo, then follow `ADOPT_FROM_HISTORY.md` to back-fill this vault from your last 30 days.
> - [ ] Add your own data-stack skills under `.claude/skills/` (the company-specific ones from the
>       original vault have been stripped; bring your own Mixpanel / Metabase / analytics skills).

BANNER
say "CLAUDE.md (operating manual + adapt banner)"
[ -f "$SRC/.gitignore" ] && cp "$SRC/.gitignore" "$VT/.gitignore"
rsync -aq "$SRC/.obsidian/" "$VT/.obsidian/" --exclude='workspace*' --exclude='.DS_Store' 2>/dev/null && say ".obsidian/ (config; workspace stripped)"

# --- System: templates + generic scripts + architecture docs (NO dashboards content) ---
rsync -aq "$SRC/System/templates/" "$VT/System/templates/" && say "System/templates/"
rsync -aq "$SRC/System/scripts/" "$VT/System/scripts/" --exclude='.DS_Store' --exclude='VaultRecorder'
rm -rf "$VT/System/scripts/__pycache__"
rm -f "$VT/System/scripts/"{clone-bundle,clone-restore,build-merge-payload,build-starter-kit}.sh
say "System/scripts/ (generic infra; binary + personal migration scripts stripped)"
mkdir -p "$VT/System/docs"
# System/docs sourcing (keep this honest — the seam that hid the onboarding bugs):
#   - WORK_MACHINE_SETUP.md, NOTEBOOKLM.md : copied verbatim from the source vault.
#   - OUR_SYSTEM.md → HOW_THIS_SYSTEM_WORKS.md : the vault holds the generic paradigm doc as
#     OUR_SYSTEM.md; regen renames it. Edit OUR_SYSTEM.md in the vault, not the template copy.
#   - USING_THE_HARNESS.md : TEMPLATE-CURATED (generic; the vault's copy is domain-specific, so it
#     is NOT sourced here). Edit it directly in vault-template/ and commit. The drift guard below
#     won't flag it (regen never writes it).
for d in WORK_MACHINE_SETUP.md NOTEBOOKLM.md; do
  [ -f "$SRC/System/docs/$d" ] && cp "$SRC/System/docs/$d" "$VT/System/docs/$d"
done
[ -f "$SRC/System/docs/OUR_SYSTEM.md" ] && cp "$SRC/System/docs/OUR_SYSTEM.md" "$VT/System/docs/HOW_THIS_SYSTEM_WORKS.md" && say "System/docs/ (architecture + HOW_THIS_SYSTEM_WORKS)"

# --- empty operational files (structure, no content) ---
mkdir -p "$VT/System/dashboards" "$VT/System/handoffs"
printf '# Open Items\n\n## Inbox (unsorted)\n\n## Active\n\n## Done\n' > "$VT/System/dashboards/Open Items.md"
: > "$VT/System/handoffs/.gitkeep"
cat > "$VT/System/daily-jobs.yaml" <<'YAML'
# daily-jobs.yaml — scheduled refreshes run by /start-work. EXAMPLE; replace with your own jobs.
# jobs:
#   - id: my-tracker-daily
#     desc: "pull my metric → cache → publish"
#     cmd: "bash ~/Documents/<your-vault>/Notes/<project>/scripts/run_daily.sh"
#     freshness_hours: 24
#     dow: "*"            # or "2" for Tuesdays only
#     on_fail: warn
YAML

# --- cross-cutting Bases VIEW definitions (navigation structure), no populated notes ---
for nav in Categories Subjects; do
  mkdir -p "$VT/$nav"
  rsync -aq "$SRC/$nav/" "$VT/$nav/" --include='*/' --include='*.base' --include='*.md' --exclude='*' 2>/dev/null
done

# --- empty taxonomy + READMEs ---
mkdir -p "$VT/Daily" "$VT/Notes" "$VT/People" "$VT/Meta" "$VT/Glossary"/{metrics,products,tools}
: > "$VT/Daily/.gitkeep"; : > "$VT/Notes/.gitkeep"
for g in metrics products tools; do : > "$VT/Glossary/$g/.gitkeep"; done
printf '# Notes\n\nOne folder per project. Scaffold with `/new-project` (README, PROJECT_LOG, PROJECT_ARC, spec, decisions/, research/, supporting_docs/, docs/, meetings/, KNOWLEDGE_BASE.md).\n' > "$VT/Notes/README.md"
printf '# People\n\nOne canonical note per person; wikilink `[[Name]]`. Template: System/templates/entity.md.\n' > "$VT/People/README.md"
printf '# Glossary\n\nCanonical note per metric/product/tool (with `aliases:`). metrics/ products/ tools/.\n' > "$VT/Glossary/README.md"
printf '# Memory — onboarding context (fill via /onboard)\n\n> Who you are (role, team, scope), key people, tools, processes. Read at the start of every session.\n' > "$VT/Meta/memory.md"
printf '# Agent message board\n\n```\n### [timestamp]\n⏳ → TO: [Agent] | FROM: [Agent]\n[message]\n```\nResolved: ⏳→✅ + **Resolution:**.\n' > "$VT/Meta/agent-messages.md"
say "empty taxonomy (Daily, Notes, People, Glossary, Meta, Categories, Subjects) + READMEs"

echo "✓ vault-template regenerated. Review with: git -C \"$REPO\" status vault-template"

# Idempotency guard: if regen changed committed template files, the source vault and the
# committed template have DRIFTED (someone edited one but not the other — the seam that let
# the onboarding bugs hide). Surface it so it gets reconciled + committed, never shipped silently.
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "$REPO" diff --quiet -- vault-template 2>/dev/null; then
    say "✓ idempotent — vault-template/ matches the source vault (no drift)"
  else
    say "⚠ DRIFT — regen changed vault-template/. The committed template diverged from the source vault:"
    git -C "$REPO" diff --stat -- vault-template 2>/dev/null | sed 's/^/    /'
    say "  Reconcile: commit the regen (git -C \"$REPO\" add -A vault-template) or fix the source, then re-run."
  fi
fi
