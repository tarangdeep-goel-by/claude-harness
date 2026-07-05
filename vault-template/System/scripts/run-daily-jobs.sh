#!/bin/bash
# Daily-jobs runner — invoked by /start-work at the first session of the day.
# Runs each job in System/daily-jobs.yaml only if its last success is older than
# freshness_hours (or --force). Records successes/failures in ~/vault/logs/daily-jobs.jsonl
# and writes the day marker System/handoffs/<date>/_day-started.json.
#
# Usage: run-daily-jobs.sh [--force]
set -uo pipefail

VAULT="$HOME/Documents/vault-work"
MANIFEST="$VAULT/System/daily-jobs.yaml"
LOG="$HOME/vault/logs/daily-jobs.jsonl"
DAY=$(date +%F)
DAYDIR="$VAULT/System/handoffs/$DAY"
MARKER="$DAYDIR/_day-started.json"
NOW=$(date +%s); NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
FORCE=0; [ "${1:-}" = "--force" ] && FORCE=1
mkdir -p "$DAYDIR" "$(dirname "$LOG")"

[ -f "$MANIFEST" ] || { echo "no manifest at $MANIFEST"; exit 0; }

# Parse the manifest (stdlib only) → tab-separated: name<TAB>cmd<TAB>freshness_hours<TAB>on_fail<TAB>desc
parse_jobs() {
  MANIFEST="$MANIFEST" python3 - <<'PY'
import os, re
txt = open(os.environ["MANIFEST"]).read()
jobs, cur = [], None
for raw in txt.splitlines():
    line = raw.rstrip()
    s = line.strip()
    if not s or s.startswith("#") or s == "jobs:":
        continue
    if s.startswith("- "):
        if cur: jobs.append(cur)
        cur = {}
        s = s[2:].strip()
        if not s:
            continue
    if cur is None:
        continue
    m = re.match(r'([a-zA-Z_]+)\s*:\s*(.*)$', s)
    if m:
        k, v = m.group(1), m.group(2).strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]
        cur[k] = v
if cur: jobs.append(cur)
for j in jobs:
    print("\t".join([
        j.get("name","?"), j.get("cmd",""), str(j.get("freshness_hours","24")),
        j.get("on_fail","warn"), j.get("desc",""), str(j.get("dow",""))
    ]))
PY
}

# Seconds since the last logged success for a job (empty if never)
last_success_age() {
  local name="$1"
  LOG="$LOG" JOB="$name" NOW="$NOW" python3 - <<'PY'
import os, json, sys
log, job, now = os.environ["LOG"], os.environ["JOB"], int(os.environ["NOW"])
best = None
try:
    for ln in open(log):
        try: d = json.loads(ln)
        except: continue
        if d.get("job")==job and d.get("status")=="ok" and "ts_epoch" in d:
            best = max(best or 0, d["ts_epoch"])
except FileNotFoundError:
    pass
print("" if best is None else now - best)
PY
}

log_result() {  # name status exit dur
  printf '{"ts":"%s","ts_epoch":%s,"job":"%s","status":"%s","exit":%s,"duration_s":%s}\n' \
    "$NOW_ISO" "$NOW" "$1" "$2" "$3" "$4" >> "$LOG"
}

echo "## Daily Jobs — $DAY"
RAN=0; FAILED=0; SKIPPED=0; BLOCKED=0
SUMMARY=""

TODAY_DOW=$(date +%u)   # 1=Mon … 7=Sun
while IFS=$'\t' read -r name cmd fresh onfail desc dow; do
  [ -z "$name" ] && continue
  # day-of-week gate: a job with dow=N runs only on that weekday (e.g. dow=2 → Tuesdays)
  if [ -n "$dow" ] && [ "$dow" != "$TODAY_DOW" ]; then
    echo "  ⤬ $name — not scheduled today (dow=$dow, today=$TODAY_DOW)"
    SUMMARY+="⤬ $name (dow=$dow)\n"; SKIPPED=$((SKIPPED+1)); continue
  fi
  age=$(last_success_age "$name")
  fresh_secs=$(( ${fresh:-24} * 3600 ))
  if [ "$FORCE" -eq 0 ] && [ -n "$age" ] && [ "$age" -lt "$fresh_secs" ]; then
    h=$(( age / 3600 ))
    echo "  ✅ $name — fresh (ran ${h}h ago, freshness ${fresh}h)"
    SUMMARY+="✅ $name (fresh)\n"; SKIPPED=$((SKIPPED+1)); continue
  fi
  echo "  ▶ $name — running: $cmd"
  start=$(date +%s)
  bash -c "$cmd"; rc=$?
  dur=$(( $(date +%s) - start ))
  if [ "$rc" -eq 0 ]; then
    log_result "$name" ok 0 "$dur"
    echo "  ✅ $name — ok (${dur}s)"
    SUMMARY+="▶ $name (ok ${dur}s)\n"; RAN=$((RAN+1))
  else
    log_result "$name" fail "$rc" "$dur"
    FAILED=$((FAILED+1)); RAN=$((RAN+1))
    if [ "$onfail" = "block" ]; then
      echo "  ⛔ $name — FAILED (exit $rc) [on_fail=block]"
      SUMMARY+="⛔ $name (FAILED exit $rc — BLOCK)\n"; BLOCKED=$((BLOCKED+1))
    else
      echo "  ⚠ $name — failed (exit $rc) [on_fail=warn]"
      SUMMARY+="⚠ $name (failed exit $rc)\n"
    fi
  fi
done < <(parse_jobs)

# Write / refresh the day marker
MARKER="$MARKER" NOW_ISO="$NOW_ISO" NOW="$NOW" SUMMARY="$SUMMARY" RAN="$RAN" FAILED="$FAILED" SKIPPED="$SKIPPED" \
python3 - <<'PY' 2>/dev/null || true
import os, json
json.dump({
  "date": os.path.basename(os.path.dirname(os.environ["MARKER"])),
  "started_at": os.environ["NOW_ISO"],
  "started_ts": int(os.environ["NOW"]),
  "jobs_ran": int(os.environ["RAN"]),
  "jobs_failed": int(os.environ["FAILED"]),
  "jobs_skipped": int(os.environ["SKIPPED"]),
  "summary": [s for s in os.environ["SUMMARY"].strip().split("\\n") if s],
}, open(os.environ["MARKER"], "w"), indent=2)
PY

echo "  → marker: $MARKER (ran=$RAN failed=$FAILED blocked=$BLOCKED skipped=$SKIPPED)"
# Only a BLOCK-level failure fails the runner; warn-level failures are non-blocking
# (they're shown + logged, but /start-work should not error out over them).
[ "$BLOCKED" -gt 0 ] && exit 1 || exit 0
