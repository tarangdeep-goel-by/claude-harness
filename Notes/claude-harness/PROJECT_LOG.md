# Project Log — claude-harness

> Temporal spine for the claude-harness workspace (the Claude Code harness config: hooks, skills,
> memory infra). Newest-first. Slice on `## YYYY-MM-DD`. Throughline in `PROJECT_ARC.md`.

## 2026-07-26 · a8b1ae19 · dev · Public v0.4.0 release + Hermes mechanism #2 (skill-retrieval)

- **Dev-focused public fork v0.4.0** (`1e15739`): stripped SM-coupled skills + SM refs; brought the
  workflow-engine family (workflow-engine/task-triage/debug-escalation/done-gate/review-merge/karpathy)
  into the repo, all live-symlinked. Hardcoded `/Users/tarang` → cwd-derived slugs in memory hooks.
  Distilled `CLAUDE.md`. Removed the telemetry-upload pipeline (Drive/rclone) + gog/rclone deps.
- **Public release**: `git filter-repo` purged `plans/` (personal info) + `--force-with-lease` push;
  MIT LICENSE, README polish, generic pre-commit; PRIVATE→PUBLIC; description + topics; deleted
  `feat/memory-infra`. Repo: github.com/tarangdeep-goel-by/claude-harness.
- **Hermes #2 shipped** (`d8836ae`, `bb4984d`): `skill-retrieval-hook.sh` (UserPromptSubmit) runs
  `qmd query <prompt> -c skills -n 3` over descriptions staged by `build-skill-index.sh`; injects
  top-3 score ≥0.5 as additionalContext, silent below. Wired into settings.adopter.json + install
  + warm-start + live settings.json. 4 bugs fixed (macOS timeout, python stdin/env, import sys,
  qmd --min-score).
- Links: [[a8b1ae19]] (handoff); plan `plans/vast-splashing-wirth.md`.

## 2026-07-06 · 5927821f · dev · Memory quality loop + precompact state preservation

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
- **PreCompact state preservation (push 2, `8fe8f72`):** `precompact-hook.sh` now writes a
  deterministic state snapshot (git + active goal, CC-noise filtered) alongside the transcript export.
  Decision: no GLM on the hot path — [[0002-precompact-deterministic-snapshot]].
- Links: [[5927821f]] (handoff); commits `e1f9956` `c928f36` `fc195f1` `03e9561` `e3e63ae` `8fe8f72`.

## 2026-07-05 · prior · Memory infra #1 (dialectic infer loop) + #2 (temporal invalidation) built

- S1: GLM-4.7 Stop-hook infers durable facts → `memory-review-queue.jsonl`; `/reflect memory apply|dismiss`.
- S2: canonical frontmatter schema (nested `metadata:`); validate-hook stamps `created`/`last_verified`;
  staleness-hook flags high-conf >90d + Jaccard overlap >0.5.
- S0: safety — disabled learning-detector, archived queue, pre-memory-infra tar snapshot.

## 2026-07-27 · 887fe5e4 · dev · hook timeout fix → qmd 2.5.3 + bge-m3 embed stack repair
- Fixed UserPromptSubmit 5s timeout (skill-retrieval hook): outer 5→10s, internal 5→3s, pause-sentinel.
- qmd 1.0.7 → 2.5.3; embedding model embeddinggemma → Qwen3 → **bge-m3** (Qwen3 GGUF deadlocks bulk embed — llama.cpp eval bug, node-llama-cpp 3.18.1).
- Full brew+npm upgrade (~65 pkgs); mise+node25; npm allow-scripts set.
- bge-m3 embed running (~midday ETA), monitoring cron armed.
- Telemetry: skill-retrieval fix verified; memory-infer down (GLM z.ai out of credits — recharge); recall SKILL.md triggers strengthened.
- [[handoff: System/handoffs/2026-07-27/887fe5e4-777e-4909-8cda-8f3e7456ccee.md]]
