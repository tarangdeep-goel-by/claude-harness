# ADR 0001 — Memory quality is a closed 5-step loop, not more write machinery

**Date:** 2026-07-06 · **Status:** Accepted · **Tier:** Keystone

## Context

After #1 (dialectic infer loop) and #2 (temporal invalidation) landed, the memory subsystem could
*capture, validate, and curate* durable facts — but it could not answer "is the memory actually any
good?" Two grounding sweeps showed the loop was only half-observable: **no signal on whether a memory
is ever read** (utilization), and **no rollup** of the signals already being emitted into logs/queue/corpus.
The instinct to add *more* write/staleness hooks would have deepened capture without enabling judgment.

## Decision

Model memory quality as a closed **5-step loop** — Write → Read → Test → Track → Improve — and make
each step observable:

- **Write**: `/reflect memory apply|dismiss` flips queue status (already built; this session exercised it).
- **Read**: a PostToolUse Read hook (`memory-consulted`) records per-file consultations → utilization.
- **Test**: the hooks themselves (all non-blocking, `exit 0`); `/memory health` reports their error rate.
- **Track**: `/memory health` — one read-only rollup over queue + corpus + `hooks.jsonl` + consulted-state.
- **Improve**: `/memory review` — reads the health findings and proposes **advisory** harness tweaks.

The two quality proxies are **approval rate** (precision of capture) and **utilization** (is anything
read). The cost thesis (per-session GLM-4.7 call earning its keep) becomes visible via approval rate +
GLM error rate in the rollup.

## Rationale

- **Measurement before more machinery.** Adding hooks without a rollup deepens a log nobody reads. The
  rollup is what turns emitted signals into decisions.
- **Utilization is the best quality proxy available locally** — a memory never read is dead weight,
  regardless of its confidence stamp.
- **Advisory Improve step keeps the user as curator.** `/memory review` proposes; the user accepts/defers.
  No auto-application — prevents a feedback loop where the harness silently rewrites itself.

## Consequences

- **Positive:** The loop is now demonstrably closed — a promoted candidate is observable across
  write→read→track→improve (approval 100%, consulted counter, 3 honest findings, incl. a self-caught
  staleness-noise bug that was fixed).
- **Positive:** The honest top finding (2% canonical adoption) surfaced automatically — the system
  correctly reports that its staleness/overlap machinery has thin signal until the S3 backfill runs.
- **Negative / trade-off:** Q1 captures explicit Read-tool consults only, not warm-start injection or
  `cat`-via-Bash — "delivered to context" is a separate future signal.
- **Open:** recall (the negative case — "facts we missed") is still unmeasured; deferred until
  utilization + approval prove useful.
