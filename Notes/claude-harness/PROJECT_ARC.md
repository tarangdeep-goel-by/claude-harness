# PROJECT_ARC — claude-harness

> The throughline. Phase boundaries + pivots. Most sessions touch nothing here.

## What this is

A personal Claude Code harness: hooks, skills, and a memory infrastructure that captures durable facts
about how the user works, validates them, and now *measures their quality*. The arc is the memory
subsystem maturing from "writes things" to "knows whether the things it writes are any good."

## Phases

- **Phase 0 — Baseline import (2026-07-04).** Repo bootstrapped from a zip snapshot; existing hooks +
  skills + auto-memory corpus (messy frontmatter) imported. `7da10a0`.
- **Phase 1 — Memory write path (2026-07-05).** #1 dialectic infer loop (GLM-4.7 Stop-hook → review
  queue → `/reflect memory apply|dismiss`) and #2 temporal invalidation (canonical schema + validate +
  staleness hooks). The harness could now *capture and curate* durable facts. Commits `e1f9956`, `c928f36`.
- **Phase 2 — Memory quality loop (2026-07-06).** **CURRENT.** Closed Write→Read→Test→Track→Improve:
  utilization hook (Q1), hook-signal honesty (Q2), `/memory health` (Q3), `/memory review` (Q4),
  end-to-end done-gate (Q5). The harness can now *answer "is the memory any good?"* with evidence.
  Commit `03e9561`.

## Key pivots

- **2026-07-06 — Quality over more write machinery.** Reframed "how do we validate memory?" away from
  additional write/staleness hooks toward a *measurement* loop. Approval rate + utilization are the two
  quality proxies; the rollup makes them visible. Decision record: [[0001-memory-quality-loop]].
- **2026-07-06 — Advisory Improve step.** `/memory review` proposes tweaks but never auto-applies — the
  user stays the curator. Prevents a feedback loop where the harness silently rewrites itself.

## Current frontier

- **Adoption gap.** 193 corpus files, 2% canonical. The quality machinery works but has thin signal
  until the S3 safe-archive + backfill runs. `/memory review` surfaces this as tweak [1] automatically.
- **Pre-compaction state preservation.** vault-push captures session-end state, but a mid-session
  compaction can lose detail; the precompact hook should snapshot state too (next).
- **Recall (negative case).** "Facts we missed" is still unmeasured — needs a monthly sample-audit.
  Defer until utilization + approval prove useful.
