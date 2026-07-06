# ADR 0002 — PreCompact snapshot is deterministic (no GLM)

**Date:** 2026-07-06 · **Status:** Accepted · **Tier:** Tactical

## Context

The vault-push upgrade (project-mode handoff + PROJECT_LOG) captures session-end state. The user
flagged the asymmetry: a **mid-session compaction** can truncate context before session end, and the
PreCompact hook only exported the raw transcript — it did not preserve a *resume-point* state
snapshot. Two ways to fill the gap:

- **(a) GLM-distilled snapshot** — call glm-4.7 (like memory-infer) to synthesize a vault-push-style
  handoff (did / decisions / state-now / open-threads) at compaction.
- **(b) Deterministic snapshot** — extract git working tree + recent user prompts from the
  transcript, no model call.

## Decision

Use **(b) deterministic**. The PreCompact hook writes a state snapshot
(`~/vault/sessions/<date>_precompact_<sid8>_<hhmmss>.md`) with frontmatter (session/branch/
last_commit/transcript), the active goal (recent user prompts, CC-injected noise filtered), the git
working tree, and a resume pointer — alongside the existing transcript export.

## Rationale

- **Hot path.** PreCompact fires before compaction resumes; a network-bound GLM call (mean ~3.4s in
  memory-infer, plus failure tails) delays the user. Deterministic extraction is sub-second.
- **Non-blocking guarantee.** No network → no failure mode that could block compaction. The hook's
  `exit 0` contract is unconditional.
- **Cost.** Compaction can fire multiple times in a long session; a GLM call each time is unbounded
  new spend for a safety-net artifact.
- **Separation of concerns.** PreCompact is the safety net (preserve bytes + the thread);
  vault-push is the curated synthesis (agent-authored, session-end, in-repo). Layering them keeps
  each simple. The full transcript — the ground truth — is already exported + qmd-indexed.
- **Good enough.** Git state + active goal + transcript pointer is a complete resume index; the
  marginal value of model synthesis at compaction is low.

## Consequences

- **Positive:** Hot path stays free; non-blocking contract preserved; zero new cost; snapshot is
  deterministic and reproducible.
- **Negative / trade-off:** No synthesized "decisions/state-now" section — the snapshot is an index,
  not a summary. The full transcript (linked) and the session-end vault-push handoff cover those.
- **Upgrade path:** If the deterministic snapshot proves insufficient (reviewable via the snapshots
  themselves), a GLM distillation is a one-function addition behind the same writer — the design
  doesn't preclude it.
