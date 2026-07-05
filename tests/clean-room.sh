#!/usr/bin/env bash
# clean-room.sh — the distribution safety gate. Proves a fresh ADOPTER install + a subsequent
# update reconcile CLEANLY in a throwaway HOME, so a broken install.sh/update.sh never ships to
# adopters. Run locally before pushing, and in CI on every push/PR. Exits nonzero on any failure.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d "${TMPDIR:-/tmp}/harness-ci.XXXXXX")"
export HOME="$SB"
FAIL=0
chk(){ if [ "$2" = 0 ]; then printf '  ✓ %s\n' "$1"; else printf '  ✗ %s\n' "$1"; FAIL=1; fi; }

echo "== fresh adopter install =="
bash "$REPO/install.sh" >/dev/null 2>&1
[ -e "$SB/.claude/settings.json" ] && ! grep -q "/Users/" "$SB/.claude/settings.json"; chk "adopter settings, no personal paths" $?
{ [ ! -e "$SB/.claude/skills/analysis" ] && [ ! -e "$SB/.claude/skills/capture-journey-generic" ]; }; chk "SM-coupled skills skipped" $?
{ [ -L "$SB/.claude/skills/recall" ] && [ -L "$SB/.claude/skills/report-telemetry" ]; }; chk "generic skills linked" $?
[ -f "$SB/Documents/vault-work/CLAUDE.md" ]; chk "vault seeded" $?
grep -q harness-telemetry-report "$SB/Documents/vault-work/System/daily-jobs.yaml"; chk "telemetry daily-job seeded" $?

echo "== warm-start on the fresh vault =="
before=$(grep -c FATAL "$SB/vault/logs/warm-start-errors.log" 2>/dev/null); before=${before:-0}
printf '{"session_id":"ci","source":"startup","cwd":"%s/Documents/vault-work"}' "$SB" \
  | bash "$REPO/claude/scripts/warm-start.sh" 2>/dev/null \
  | python3 -c "import sys,json;json.load(sys.stdin)"; chk "warm-start emits valid JSON" $?
after=$(grep -c FATAL "$SB/vault/logs/warm-start-errors.log" 2>/dev/null); after=${after:-0}
[ "$after" -le "$before" ]; chk "no new warm-start FATALs on fresh vault" $?

echo "== session indexing (the value prop: an existing transcript becomes searchable) =="
# This is the surface that shipped broken: nothing exercised the session-export
# pipeline or setup-work-machine.sh. Seed a synthetic transcript, run the sync,
# and assert it lands in the sessions vault (what qmd/recall index).
SID="c1eanr00-dead-beef-cafe-000000000001"; PREFIX="${SID:0:8}"
mkdir -p "$SB/.claude/projects/testproj"
cat > "$SB/.claude/projects/testproj/$SID.jsonl" <<JSONL
{"type":"user","sessionId":"$SID","cwd":"$SB/work/widgetproj","timestamp":"2026-07-03T10:00:00Z","message":{"role":"user","content":"CLEANROOM_MARKER analyze widget pricing across regions"}}
{"type":"assistant","sessionId":"$SID","timestamp":"2026-07-03T10:00:05Z","message":{"role":"assistant","model":"claude-test","content":[{"type":"text","text":"Widget pricing: region A higher; recommend tiered pricing. CLEANROOM_MARKER"}],"usage":{"input_tokens":10,"output_tokens":20}}}
{"type":"user","sessionId":"$SID","timestamp":"2026-07-03T10:01:00Z","message":{"role":"user","content":"Thanks, that covers it."}}
JSONL
bash "$SB/vault/scripts/daily-session-sync.sh" >/dev/null 2>&1   # qmd absent in CI → export runs, embed no-ops
ls "$SB/vault/sessions/"*"${PREFIX}.md" >/dev/null 2>&1; chk "existing transcript exported → vault/sessions (indexing value-prop)" $?
grep -rq "CLEANROOM_MARKER" "$SB/vault/sessions/" 2>/dev/null; chk "exported session carries real transcript content" $?
grep -q "export-session" "$SB/vault/scripts/daily-session-sync.sh" 2>/dev/null; chk "daily-session-sync.sh is the full export version (not the qmd-only clobber)" $?
# The setup script does heavy brew/model/qmd steps unfit for CI, so assert its two
# critical fixes structurally (regression-guards the clobber + no-backfill bugs):
SETUP="$REPO/vault-template/System/scripts/setup-work-machine.sh"
grep -q "Initial Session Backfill" "$SETUP" 2>/dev/null; chk "setup runs a first-time session backfill" $?
grep -q 'if \[ ! -e "\$SYNC_SCRIPT" \]' "$SETUP" 2>/dev/null; chk "setup guards the exporter symlink (no clobber)" $?

echo "== onboarding engine: bootstrap --check + daily-jobs runner =="
bash "$REPO/bootstrap.sh" --check >"$SB/boot.out" 2>&1; rc=$?
{ [ "$rc" = 0 ] && grep -q "jq" "$SB/boot.out"; }; chk "bootstrap --check runs clean + reports deps (installs nothing)" $?
RDJ="$SB/Documents/vault-work/System/scripts/run-daily-jobs.sh"
if [ -f "$RDJ" ]; then
  bash "$RDJ" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ]; chk "run-daily-jobs exits 0 (warn-level job failures don't fail the runner)" $?
  ls "$SB/Documents/vault-work/System/handoffs/"*/_day-started.json >/dev/null 2>&1; chk "daily-jobs writes the day-started marker" $?
else
  chk "run-daily-jobs.sh seeded into the vault" 1
fi

echo "== update reconcile (prune stale · link new · keep current) =="
ln -s "$REPO/claude/skills/ghostskill" "$SB/.claude/skills/ghostskill"   # simulate a removed skill
rm -f "$SB/vault/scripts/onboarding-log.sh"                             # simulate a newly-added script not yet linked
bash "$REPO/update.sh" --no-pull >/dev/null 2>&1
[ ! -L "$SB/.claude/skills/ghostskill" ]; chk "dangling skill pruned on update" $?
[ -L "$SB/.claude/skills/recall" ]; chk "generic skill still linked after update" $?
[ -L "$SB/vault/scripts/onboarding-log.sh" ]; chk "newly-added vault script linked on update" $?

echo "== onboarding report + telemetry =="
bash "$REPO/verify-setup.sh" --json 2>/dev/null \
  | python3 -c "import sys,json;d=json.load(sys.stdin);assert all(k in d for k in ('healthy','checks','operator','onboarding_steps'))"; chk "verify-setup --json report incl. onboarding_steps" $?
python3 - "$SB/vault/logs/onboarding.jsonl" <<'PY' 2>/dev/null; chk "onboarding.jsonl records valid install + verify events" $?
import json,sys,os
p=sys.argv[1]
ev=[json.loads(l) for l in open(p)] if os.path.exists(p) else []
steps={e.get("step") for e in ev}
assert "install" in steps and "verify" in steps, steps
PY

echo "== verify-setup actually DETECTS a broken install (meta-check) =="
# On the healthy install above, the report was valid. Now break the engine and confirm
# verify flags it (healthy=false) — a check that always passes green is worthless.
rm -f "$SB/.claude/scripts/warm-start.sh"                               # break a required engine symlink
bash "$REPO/verify-setup.sh" --json 2>/dev/null \
  | python3 -c "import sys,json;d=json.load(sys.stdin);assert d['healthy'] is False and d['warn']>=1"; chk "verify-setup flags a broken install (healthy=false)" $?

rm -rf "$SB"
echo
if [ "$FAIL" = 0 ]; then echo "✓ clean-room PASSED"; else echo "✗ clean-room FAILED"; exit 1; fi
