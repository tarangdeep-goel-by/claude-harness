# Project Log — claude-harness

> Temporal spine for the claude-harness workspace (the Claude Code harness config: hooks, skills,
> memory infra). Newest-first. Slice on `## YYYY-MM-DD`. Throughline in `PROJECT_ARC.md`.

## 2026-07-06 · 5927821f · dev · Memory quality loop closed (Write/Read/Test/Track/Improve)

- **Q1–Q5 shipped + merged to main (`03e9561`).** Closed the 5-step quality loop:
  - Q1 utilization hook (`memory-consulted-hook.sh`, PostToolUse Read) → `~/vault/logs/memory-consulted.json`.
  - Q2 hook-signal enrichment: infer logs `glm=ok|empty|err appended=N`; staleness emits `outcome:"error"`.
  - Q3 `/memory health` (new `memory` skill, `memory_health.py`, `--json` mode).
  - Q4 `/memory review` (`memory_review.py`, advisory tweak proposals).
  - Q5 end-to-end done-gate: promoted `commit-on-request` (#5) → approval 100% visible; fixed a
    self-caught staleness-noise bug (`fastest_staling` floors at ≥30d).
- **Decisions:** quality = closed loop, not more write machinery ([[0001-memory-quality-loop]]);
  `/memory review` advisory-only; real-candidate test (not disposable).
- **Honest finding:** corpus is 193 files / 2% canonical adoption — the staleness/overlap machinery
  has almost nothing to chew on. Surfaced automatically by `/memory review` tweak [1].
- Links: [[5927821f]] (handoff); commits `e1f9956` `c928f36` `fc195f1` `03e9561`.

## 2026-07-05 · prior · Memory infra #1 (dialectic infer loop) + #2 (temporal invalidation) built

- S1: GLM-4.7 Stop-hook infers durable facts → `memory-review-queue.jsonl`; `/reflect memory apply|dismiss`.
- S2: canonical frontmatter schema (nested `metadata:`); validate-hook stamps `created`/`last_verified`;
  staleness-hook flags high-conf >90d + Jaccard overlap >0.5.
- S0: safety — disabled learning-detector, archived queue, pre-memory-infra tar snapshot.
