#!/usr/bin/env python3
"""infra_health.py — telemetry rollup for the Claude Code harness.

Reads the event sinks under ~/vault/logs and prints a performance report:
  - hooks: per-hook count, failure/skip rate, p50/p95 duration (hooks.jsonl)
  - skills: cost (median output tokens) + quality (correction rate) + auto/explicit (skills.jsonl)
  - routing adherence: ok/missed/misfire on trigger-matched turns (routing.jsonl)
  - subagents: invocation frequency (skills.jsonl kind=agent)
  - dead skills: registry minus ever-invoked (skills.jsonl ∪ workflow.jsonl real-time)
  - daily jobs: last run + freshness + failures (daily-jobs.jsonl)
  - sessions: live vs unpushed (active-sessions/)
  - recent errors (warm-start-errors.log)

Skill/routing telemetry is produced offline by skill_analyzer.py in the session-export
pipeline; see ~/code/claude-harness/vault-scripts/TELEMETRY.md for the full schema.

Usage: infra_health.py [days]   (default 7)
"""
import json, os, sys, time, glob
from collections import defaultdict
from datetime import datetime

HOME = os.path.expanduser("~")
LOGS = f"{HOME}/vault/logs"
DAYS = int(sys.argv[1]) if len(sys.argv) > 1 else 7
CUTOFF = time.time() - DAYS * 86400


def parse_ts(d):
    if "ts_epoch" in d:
        return d["ts_epoch"]
    ts = d.get("ts", "")
    if not ts:
        return None
    try:
        # Handles both whole-second and fractional (".263Z") ISO timestamps, UTC.
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def read_jsonl(path):
    if not os.path.exists(path):
        return
    for ln in open(path):
        try:
            yield json.loads(ln)
        except Exception:
            continue


def pct(vals, p):
    if not vals:
        return None
    s = sorted(vals)
    return s[min(len(s) - 1, int(round((p / 100) * (len(s) - 1))))]


print(f"# Infra Health — last {DAYS}d\n")

# ── Hooks (hooks.jsonl + rotated backups) ──────────────────────────────
counts = defaultdict(int)
out = defaultdict(lambda: defaultdict(int))
durs = defaultdict(list)          # milliseconds
events = defaultdict(set)         # which CC events drove each hook
nonzero_exit = defaultdict(int)   # exit_code != 0 (independent of outcome label)
for src in ("hooks.jsonl", "hooks.jsonl.1", "hooks.jsonl.2"):
    for d in read_jsonl(f"{LOGS}/{src}"):
        t = parse_ts(d)
        if t is None or t < CUTOFF:
            continue
        h = d.get("hook", "?")
        counts[h] += 1
        out[h][d.get("outcome", "?")] += 1
        if d.get("event"):
            events[h].add(d["event"])
        ec = d.get("exit_code")
        if isinstance(ec, int) and ec != 0:
            nonzero_exit[h] += 1
        # Prefer duration_ms; fall back to legacy duration_s.
        if "duration_ms" in d:
            try: durs[h].append(float(d["duration_ms"]))
            except Exception: pass
        elif "duration_s" in d:
            try: durs[h].append(float(d["duration_s"]) * 1000.0)
            except Exception: pass

print("## Hooks")
print(f"{'hook':18} {'event':13} {'runs':>5} {'ok':>5} {'skip':>5} {'err':>4} {'exit≠0':>6} {'p50ms':>6} {'p95ms':>6} {'maxms':>6}")
for h in sorted(counts, key=lambda x: -counts[x]):
    o = out[h]
    # "err" = blocking/error outcomes (block is intentional for guard hooks; flag only true errors)
    err = sum(v for k, v in o.items() if k in ("error", "fail"))
    blocked = o.get("block", 0) + o.get("deny", 0)
    p50 = pct(durs[h], 50)
    p95 = pct(durs[h], 95)
    mx = max(durs[h]) if durs[h] else None
    ev = ",".join(sorted(events[h])) or "-"
    flag = "  ⚠" if (err or nonzero_exit[h]) else ""
    okc = o.get("ok", 0) + o.get("allow", 0) + o.get("pass", 0)
    print(f"{h:18} {ev:13.13} {counts[h]:>5} {okc:>5} {o.get('skip',0):>5} {err:>4} {nonzero_exit[h]:>6} "
          f"{(f'{p50:.0f}' if p50 is not None else '-'):>6} "
          f"{(f'{p95:.0f}' if p95 is not None else '-'):>6} "
          f"{(f'{mx:.0f}' if mx is not None else '-'):>6}{flag}")
    if blocked:
        print(f"{'':18} {'':13} ↳ {blocked} block/deny (guard working as intended)")
if not counts:
    print("  (no hook events in window)")

# ── Skills: quality + cost (skills.jsonl) ──────────────────────────────
from statistics import median

skl = defaultdict(lambda: {"n": 0, "auto": 0, "explicit": 0, "tok": [],
                           "corr": 0, "err": 0})
agents = defaultdict(int)
for d in read_jsonl(f"{LOGS}/skills.jsonl"):
    t = parse_ts(d)
    if t is None or t < CUTOFF:
        continue
    if d.get("kind") == "agent":
        agents[d.get("skill", "?")] += 1
        continue
    s = skl[d.get("skill", "?")]
    s["n"] += 1
    src = d.get("source", "auto")
    s[src] = s.get(src, 0) + 1
    if d.get("output_tokens"):
        s["tok"].append(d["output_tokens"])
    if d.get("correction_next"):
        s["corr"] += 1
    s["err"] += d.get("errors", 0)

print("\n## Skills — quality + cost")
if skl:
    print(f"  {'skill':22} {'inv':>4} {'auto':>4} {'expl':>4} {'med_out_tok':>11} {'corr%':>6} {'err':>4}")
    for n in sorted(skl, key=lambda x: -skl[x]["n"]):
        s = skl[n]
        med = int(median(s["tok"])) if s["tok"] else 0
        corr = (100 * s["corr"] / s["n"]) if s["n"] else 0
        flag = "  ⚠ rework" if corr >= 25 else ""
        print(f"  {n:22} {s['n']:>4} {s.get('auto',0):>4} {s.get('explicit',0):>4} "
              f"{med:>11,} {corr:>5.0f}% {s['err']:>4}{flag}")
else:
    print("  (no skill invocations in window — analyzer runs on session export)")

# ── Routing adherence (routing.jsonl) ──────────────────────────────────
rv = defaultdict(int)
missed = []
for d in read_jsonl(f"{LOGS}/routing.jsonl"):
    t = parse_ts(d)
    if t is None or t < CUTOFF:
        continue
    rv[d.get("verdict", "?")] += 1
    if d.get("verdict") == "missed":
        missed.append(d)
ok, ms, mf = rv.get("ok", 0), rv.get("missed", 0), rv.get("misfire", 0)
print("\n## Routing adherence")
if ok + ms:
    print(f"  adherence = {100*ok/(ok+ms):.0f}%   ({ok} fired / {ms} missed)"
          f"   + {mf} misfire candidate(s)")
    for d in missed[-6:]:
        print(f"   ⚠ missed {','.join(d.get('matched', []))}: \"{d.get('prompt','')[:55]}\"")
else:
    print("  (no trigger-matched turns in window)")

# ── Dead skills (registry minus ever-seen) ─────────────────────────────
reg = {os.path.basename(os.path.dirname(p))
       for p in glob.glob(os.path.expanduser("~/.claude/skills/*/SKILL.md"))}
seen = set(skl.keys())
for d in read_jsonl(f"{LOGS}/skills.jsonl"):      # all-time, ignore window
    if d.get("kind") != "agent":
        seen.add(d.get("skill"))
for d in read_jsonl(f"{LOGS}/workflow.jsonl"):    # real-time invocation sink (merged tool-telemetry hook)
    if d.get("kind") in ("skill", "agent"):
        seen.add(d.get("skill") or d.get("name"))
dead = sorted(reg - seen)
print("\n## Dead skills (registered, never invoked)")
print("  " + (", ".join(dead) if dead else "(none — every registered skill has been used)"))

print("\n## Subagents (invocations)")
if agents:
    for n in sorted(agents, key=lambda x: -agents[x]):
        print(f"  {n:24} {agents[n]:>4}")
else:
    print("  (none in window)")

# ── Daily jobs (daily-jobs.jsonl) ──────────────────────────────────────
print("\n## Daily Jobs")
last = {}
for d in read_jsonl(f"{LOGS}/daily-jobs.jsonl"):
    job = d.get("job", "?")
    prev = last.get(job)
    if not prev or d.get("ts_epoch", 0) >= prev.get("ts_epoch", 0):
        last[job] = d
if last:
    now = time.time()
    for job, d in sorted(last.items()):
        age_h = (now - d.get("ts_epoch", now)) / 3600
        mark = "✅" if d.get("status") == "ok" else "⚠"
        print(f"  {mark} {job:24} last={d.get('status','?')} {age_h:.0f}h ago (exit {d.get('exit','?')})")
else:
    print("  (no daily-job runs logged)")

# ── Knowledge drift (knowledge-drift-score.jsonl) — semantic-memory eval KPI ──
print("\n## Knowledge Drift (semantic-memory KPI)")
kd = list(read_jsonl(f"{LOGS}/knowledge-drift-score.jsonl"))
if kd:
    def _adr(d):
        return (d.get("adr_missing_status", 0) + d.get("adr_stray_enum", 0)
                + d.get("adr_dangling_links", 0) + d.get("adr_superseded_unmarked", 0))
    cur = kd[-1]
    print(f"  latest {cur.get('date','?')}: ADR-issues={_adr(cur)}  "
          f"KB-past-verify_by={cur.get('kb_past_verify_by',0)} (max {cur.get('kb_max_stale_days',0)}d)  "
          f"metric-drift={cur.get('metric_drift_count',0)}  "
          f"memory={cur.get('memory_count','?')} (idx {cur.get('memory_index_kb','?')}KB)  "
          f"recurring={cur.get('suspects_recurring',0)}")
    trend = kd[-6:]
    if len(trend) > 1:
        print("  trend: " + "  ".join(
            f"{d.get('date','?')[5:]}[adr{_adr(d)} md{d.get('metric_drift_count',0)} kb{d.get('kb_past_verify_by',0)}]"
            for d in trend))
    warns = []
    if _adr(cur) > 0:
        warns.append(f"⚠ {_adr(cur)} ADR-hygiene issue(s) off baseline (0) — drift crept back or a --no-verify landed")
    if cur.get("kb_past_verify_by", 0) > 0:
        warns.append(f"⚠ {cur['kb_past_verify_by']} KB(s) past verify_by, unaddressed")
    if cur.get("suspects_recurring", 0) > 0:
        warns.append(f"⚠ {cur['suspects_recurring']} suspect(s) recurring from last run — DEAD-DETECTOR alarm")
    try:
        age_d = (time.time() - time.mktime(time.strptime(cur.get("date", ""), "%Y-%m-%d"))) / 86400
        if age_d > 10:
            warns.append(f"⚠ last --score was {age_d:.0f}d ago — the weekly scan isn't running")
    except Exception:
        pass
    print("\n".join(f"  {w}" for w in warns) if warns else "  ✓ within baseline — machinery holding")
else:
    print("  (no score runs logged — seed with: discrepancy-scan.py --score)")

# ── Sessions (active-sessions/) ────────────────────────────────────────
live = unpushed = total = 0
now = time.time()
for f in glob.glob(f"{LOGS}/active-sessions/*.json"):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    total += 1
    if now - d.get("last_active_ts", 0) <= 45 * 60:
        live += 1
    if not d.get("pushed"):
        unpushed += 1
print("\n## Sessions")
print(f"  markers={total}  live(<45m)={live}  unpushed={unpushed}")

# ── Recent errors ──────────────────────────────────────────────────────
errlog = f"{LOGS}/warm-start-errors.log"
if os.path.exists(errlog):
    errs = [l for l in open(errlog) if "FATAL" in l or "ERROR" in l]
    print("\n## Recent warm-start errors")
    print(f"  {len(errs)} FATAL/ERROR lines total" + (f"; last: {errs[-1].strip()[:90]}" if errs else ""))

# ── warm-start brief health (truncated / degraded context) ─────────────
# The old warm-start row was hardcoded outcome:ok / exit_code:0, so a half-length
# brief scored as a clean success. Now the hook logs brief_len + a real outcome;
# surface it so a degraded run is loud here instead of silent.
ws_lens, ws_degraded_runs = [], 0
for src in ("hooks.jsonl", "hooks.jsonl.1", "hooks.jsonl.2"):
    for d in read_jsonl(f"{LOGS}/{src}"):
        if d.get("hook") != "warm-start":
            continue
        t = parse_ts(d)
        if t is None or t < CUTOFF:
            continue
        bl = d.get("brief_len")
        if isinstance(bl, int):
            ws_lens.append(bl)
        if d.get("outcome") == "degraded":
            ws_degraded_runs += 1
if ws_lens or ws_degraded_runs:
    flag = "  ⚠ DEGRADED RUNS — expected context truncated (see error log above)" if ws_degraded_runs else ""
    print("\n## warm-start brief health")
    lo = min(ws_lens) if ws_lens else "-"
    p50 = pct(ws_lens, 50)
    print(f"  runs_with_len={len(ws_lens)}  degraded={ws_degraded_runs}  "
          f"brief_len min={lo} p50={p50 if p50 is not None else '-'}{flag}")
