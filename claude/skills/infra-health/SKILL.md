---
name: infra-health
description: "Telemetry on the Claude Code harness itself — how hooks, skills, subagents, and daily jobs are performing. Use for: \"infra health\", \"how is the infra performing\", \"hook telemetry\", \"which skills am I using\", \"are any hooks failing\", \"infra stats\". All telemetry is LOCAL (stays on this machine under ~/vault/logs/). Distinct from /stats (which is cost/token usage)."
---

# /infra-health — Harness Telemetry

Reports how the infrastructure is performing, so it can be improved. Reads the event sinks
under `~/vault/logs/` — no live cost data (that's `/stats`). **All telemetry is local** — nothing
leaves this machine.

## Run it

```bash
python3 ~/.claude/skills/infra-health/scripts/infra_health.py <days>   # default 7
```
- `/infra-health` → 7 days · `/infra-health today` → `1` · `/infra-health month` → `30`

## What it shows
- **Hooks** — per-hook run count, ok/skip/error split, p50/p95 duration. ⚠ flags any hook with
  errors/blocks. Source: `hooks.jsonl`.
- **Skills — quality + cost** — per skill: invocations, auto vs explicit (`/slash`) split,
  median output tokens (cost), correction rate (`corr%`, ⚠ at ≥25% = rework), and in-window
  errors. Source: `skills.jsonl`.
- **Routing adherence** — `ok / (ok + missed)`: are skills firing when a prompt matches their
  triggers? Lists recent `missed` (matched triggers, nothing fired) + misfire candidates.
  Source: `routing.jsonl`.
- **Dead skills** — registered (`~/.claude/skills/*/SKILL.md`) but never invoked. Source:
  `skills.jsonl` ∪ `workflow.jsonl` (all-time), minus the registry.
- **Subagents** — Task/agent invocation frequency. Source: `skills.jsonl` (`kind=agent`).
- **Daily jobs** — last run, freshness (hours ago), failures. Source: `daily-jobs.jsonl`.
- **Knowledge drift** — the semantic-memory eval KPI: latest counters + trend across recent runs
  (ADR hygiene, KBs past `verify_by` + max stale days, metric-drift suspects, memory count/index KB).
  ⚠ flags any counter climbing off its baseline, `suspects_recurring > 0` (a flagged item still
  unactioned a run later — the dead-detector alarm), or a stale `date` (the weekly `--score` isn't
  running). Working = counters flat-low + nothing recurring. Source: `knowledge-drift-score.jsonl`.
- **Sessions** — marker count, live (<45m heartbeat), and unpushed count. Source:
  `active-sessions/`.
- **Recent errors** — warm-start FATAL/ERROR tail.

## How telemetry is captured (the data model)
Two capture paths: **hooks** log themselves on the hot path; **skill/routing** quality is
computed **offline** by `skill_analyzer.py` in the session-export pipeline (a `Skill`-tool
PostToolUse hook can't measure skills — the tool returns once SKILL.md *loads*, before the skill
does any work). Full schema: `~/code/claude-harness/vault-scripts/TELEMETRY.md`.

| Sink | Written by | Holds |
|------|-----------|-------|
| `~/vault/logs/hooks.jsonl` | every hook (via `hooklib.sh`) | hook runs + outcome + duration + exit code |
| `~/vault/logs/skills.jsonl` | `skill_analyzer.py` (session-export, offline) | per-invocation cost + quality: source, output_tokens, tool_calls, errors, correction_next; `kind=agent` for subagents |
| `~/vault/logs/routing.jsonl` | `skill_analyzer.py` (session-export, offline) | per trigger-matched user turn: verdict (`ok`/`missed`/`misfire`), matched, fired, prompt |
| `~/vault/logs/workflow.jsonl` | `tool-telemetry-hook.sh` (PostToolUse `Skill\|Task`) — the merged hook | real-time skill + subagent invocations: `kind` (skill/agent), name, project, args, outcome. The single invocation log (absorbed skill-log-hook + the old events.jsonl). Dead-skill history + invocation audit; also read by workflow-gate + vault-audit. |
| `~/vault/logs/daily-jobs.jsonl` | `run-daily-jobs.sh` | daily-job success/failure + timing |
| `~/vault/logs/knowledge-drift-score.jsonl` | `discrepancy-scan.py --score` (weekly, via `/wrap-up`) | semantic-memory drift KPI: ADR-hygiene + KB-freshness + metric-drift + memory counters per run (eval trend); baseline = 2026-07-02 audit |
| `~/vault/logs/active-sessions/*.json` | `session-marker-hook.sh` | per-session liveness + pushed flag |

## Using it to improve
- A hook with a high **error/block** rate or a fat **p95** → fix or raise its timeout. (`block`/`deny`
  with `exit=2` on a guard hook is *working as intended*, not a failure — `exit_code` flags real crashes.)
- A skill with a high **`corr%`** (≥25%) → its output keeps getting reworked next turn; tighten it.
- A skill with high **median output tokens** → cost target to optimize.
- Low **routing adherence** / recurring **missed** triggers → a CLAUDE.md routing-rule gap or weak
  SKILL.md `description` triggers (matching is heuristic — treat missed/misfire as review candidates).
- A skill with **0 invocations** over a month → candidate to retire or fix discoverability.
- A daily job **stale** beyond its freshness → cron/`/start-work` not firing.
- A persistent **unpushed** count → sessions ending without `/vault-push`.
- Suggest concrete changes based on the numbers; this is the feedback loop for the harness.

> Note: skill/routing telemetry is reconstructed from session JSONL by `skill_analyzer.py`, so it
> accumulates from when that analyzer was wired into session-export. The analyzer is idempotent
> (dedup-keyed), so Stop/PreCompact re-runs over a growing JSONL never double-count.
