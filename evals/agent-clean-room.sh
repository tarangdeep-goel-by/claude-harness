#!/usr/bin/env bash
# agent-clean-room.sh — the BEHAVIORAL eval: can a real agent actually DO the things the harness
# promises, on a fresh install? Complements tests/clean-room.sh (which only checks files/symlinks).
# It stands up a fresh adopter install in a throwaway HOME, then drives headless `claude -p` through
# a few capability cases and asserts on SIDE EFFECTS (hooks fired, files written, tooling ran).
#
# MAINTAINER-RUN, not CI: it needs Claude auth + spends real tokens (CI can't auth). Reads auth from
# the environment — NO token is stored in this file:
#   export ANTHROPIC_BASE_URL=https://api.anthropic.com
#   export ANTHROPIC_AUTH_TOKEN=sk-ant-...            # billed pay-as-you-go at API rates
#   ./evals/agent-clean-room.sh
# Optional: EVAL_MODEL (default Haiku — cases test the harness, not model smarts).
set -uo pipefail

: "${ANTHROPIC_AUTH_TOKEN:?export ANTHROPIC_AUTH_TOKEN (and ANTHROPIC_BASE_URL) first}"
: "${ANTHROPIC_BASE_URL:?export ANTHROPIC_BASE_URL=https://api.anthropic.com}"
MODEL="${EVAL_MODEL:-claude-haiku-4-5-20251001}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v claude >/dev/null || { echo "✗ claude CLI not found"; exit 1; }
command -v python3 >/dev/null || { echo "✗ python3 required"; exit 1; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/agent-eval.XXXXXX")"
REAL_HOME="$HOME"   # capture before the sandbox override — lets the /recall case reuse the real qmd models
export HOME="$SB"
trap 'rm -rf "$SB"' EXIT
VAULT="$SB/Documents/vault-work"
FAIL=0; TOTAL_COST=0

echo "== fresh adopter install into $SB =="
bash "$REPO/install.sh" >/dev/null 2>&1
[ -d "$VAULT" ] || { echo "✗ install did not seed a vault"; exit 1; }

# run_agent <prompt> — headless, isolated, cheap; echoes the result text; adds cost to TOTAL_COST.
run_agent() {
  local out="$SB/agent-out.json" attempt
  for attempt in 1 2; do
    ( cd "$VAULT" && claude -p "$1" --model "$MODEL" --output-format json \
        --permission-mode bypassPermissions >"$out" 2>"$SB/agent-err.txt" )
    # transient API rate-limit (429) → back off once and retry, so a maintainer run
    # doesn't flake on throttling (esp. when cases run back-to-back).
    if [ "$attempt" = 1 ] && grep -qiE 'rate.?limit|"?is_error"?:true|Request rejected \(429\)|API Error' "$out" 2>/dev/null; then
      sleep 30; continue
    fi
    break
  done
  python3 - "$out" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1])); d=d[-1] if isinstance(d,list) else d
    print("RESULT::"+(d.get("result","") or "").replace("\n"," "))
    print("COST::"+str(d.get("total_cost_usd",0) or 0))
except Exception as e:
    print("RESULT::<parse-error: %s>"%e); print("COST::0")
PY
}
add_cost(){ TOTAL_COST=$(python3 -c "print(round($TOTAL_COST + ($1 or 0), 6))"); }
chk(){ if [ "$2" = 0 ]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAIL=1; fi; }

# ── Case 1: context injection — SessionStart/warm-start fires for the agent session ──────────
echo "== case 1: warm-start injects context on session start =="
o=$(run_agent "In one short line, what git branch is this repo on? Answer from the context you were given.")
c=$(printf '%s\n' "$o" | sed -n 's/^COST:://p'); add_cost "$c"
grep -q '"hook":"warm-start"' "$SB/vault/logs/hooks.jsonl" 2>/dev/null; chk "warm-start hook fired (context injected)" $?
printf '%s\n' "$o" | sed -n 's/^RESULT:://p' | grep -qi 'main'; chk "agent read the injected git context (said 'main')" $?

# ── Case 2: the agent can find + run harness tooling (`infra-health` collector, dry-run) ────
echo "== case 2: agent runs harness tooling =="
o=$(run_agent "Run this exact command and report the last line of its output verbatim: bash ~/.claude/skills/infra-health/scripts/collect_telemetry.sh --dry-run")
c=$(printf '%s\n' "$o" | sed -n 's/^COST:://p'); add_cost "$c"
printf '%s\n' "$o" | sed -n 's/^RESULT:://p' | grep -qiE 'bundle|dry-run|staged'; chk "agent executed the collector + reported its output" $?

# ── Case 3: the agent can write into the vault structure ─────────────────────────────────────
echo "== case 3: agent writes a note into the vault =="
o=$(run_agent "Create the file Notes/eval-check/hello.md containing exactly the single word: WORKS")
c=$(printf '%s\n' "$o" | sed -n 's/^COST:://p'); add_cost "$c"
grep -qx 'WORKS' "$VAULT/Notes/eval-check/hello.md" 2>/dev/null; chk "agent wrote Notes/eval-check/hello.md" $?

# ── Case 4: /start-work fires the day engine (runs daily-jobs, writes the day marker) ─────────
echo "== case 4: /start-work runs the day engine =="
o=$(run_agent "/start-work")
c=$(printf '%s\n' "$o" | sed -n 's/^COST:://p'); add_cost "$c"
ls "$VAULT/System/handoffs/"*/_day-started.json >/dev/null 2>&1; chk "/start-work wrote the day-started marker" $?

# ── Case 5: /vault-push persists a session handoff (the continuity value-prop) ────────────────
echo "== case 5: /vault-push persists a session handoff =="
o=$(run_agent "/vault-push")
c=$(printf '%s\n' "$o" | sed -n 's/^COST:://p'); add_cost "$c"
# /vault-push is mode-aware: PROJECT mode (cwd under Notes/<project>) writes a handoff under
# System/handoffs/<date>/; DEFAULT mode (this sandbox — cwd is the vault root, no project) appends
# the daily journal ~/vault/daily/<date>.md. Accept either persistence artifact.
{ ls "$VAULT/System/handoffs/"*/*.md 2>/dev/null; ls "$SB/vault/daily/"*.md 2>/dev/null; } | grep -q .; chk "/vault-push persisted a handoff or daily-journal entry" $?

# ── Case 6: /recall surfaces indexed content (needs qmd + its models) ─────────────────────────
echo "== case 6: /recall finds indexed content =="
if command -v qmd >/dev/null 2>&1 && [ -d "$REAL_HOME/.cache/qmd/models" ]; then
  mkdir -p "$SB/.cache/qmd" "$SB/.config/qmd" "$SB/vault/sessions"
  ln -s "$REAL_HOME/.cache/qmd/models" "$SB/.cache/qmd/models"   # reuse the 2GB models; fresh isolated index
  printf '%s\n' "---" "date: 2026-07-03" "session_id: receval" "---" \
    "# Widget pricing recall check" "QMDRECALLCASE — the northeast tiered pricing analysis lives in this session." \
    > "$SB/vault/sessions/2026-07-03_recall-eval_receval.md"
  cat > "$SB/.config/qmd/index.yml" <<YML
collections:
  sessions:
    path: ~/vault/sessions
  projects:
    path: ~/Documents/vault-work/Notes
  handoffs:
    path: ~/Documents/vault-work/System/handoffs
YML
  qmd update >/dev/null 2>&1; qmd embed >/dev/null 2>&1
  o=$(run_agent "/recall QMDRECALLCASE northeast tiered pricing")
  c=$(printf '%s\n' "$o" | sed -n 's/^COST:://p'); add_cost "$c"
  printf '%s\n' "$o" | sed -n 's/^RESULT:://p' | grep -qiE 'northeast|tiered|widget|recall-eval|QMDRECALLCASE'; chk "/recall surfaced the seeded session" $?
else
  echo "  (skipped — qmd/models absent; the search spine itself is covered by evals/qmd-recall.sh)"
fi

# ── Case 7: /wrap-up rolls the day's session handoffs into _day.md ─────────────────────────────
echo "== case 7: /wrap-up rolls up the day =="
o=$(run_agent "/wrap-up")
c=$(printf '%s\n' "$o" | sed -n 's/^COST:://p'); add_cost "$c"
ls "$VAULT/System/handoffs/"*/_day.md >/dev/null 2>&1; chk "/wrap-up produced the _day.md rollup" $?

echo
echo "total agent cost this run: \$$TOTAL_COST  (model: $MODEL)"
if [ "$FAIL" = 0 ]; then echo "✓ agent-clean-room PASSED"; else echo "✗ agent-clean-room FAILED"; exit 1; fi
