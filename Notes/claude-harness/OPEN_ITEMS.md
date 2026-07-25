# OPEN_ITEMS — claude-harness

Project-level todos. Vault-push owns this file: add new, tick done, carry the rest.
Cross-cutting/ops todos live in the global `System/dashboards/Open Items.md` (not this file).

## Skill retrieval + sync (2026-07-26)

- [ ] **Confirm skill-retrieval end-to-end.** A `qmd embed -f` was killed mid-run (may have half-done
      the embeddings); `build-skill-index.sh` rebuild was in flight at session end. Verify `qmd query
      "fix failing test" -c skills` returns debug-escalation AND the live hook emits for a debug
      prompt. [src: handoff a8b1ae19]
- [ ] **Sync architecture decision (pending user).** Option A: split personal →
      `~/.claude/settings.local.json` + symlink `settings.json` → repo `settings.adopter.json` +
      SessionStart re-link guard (true bidirectional auto-sync). vs leave-as-is (manual per-hook add).
- [ ] **Hermes mechanism #1 — autonomous skill-distillation Stop hook.** Stop hook → `skill-creator`
      drafts candidate SKILL.md into a review queue after a hard task verifies green. Deferred
      (separate plan); compounds with #2.
- [x] **Hermes mechanism #2 — skill retrieval at task-start.** Shipped (`d8836ae`, `bb4984d`).
      (2026-07-26)

## Memory infra

- [ ] **S3 safe-archive (~19 files).** User-scoped to "safe archive only." Archive the ~19 pure-noise
      corpus files, then backfill high-value files onto the canonical schema so `/memory review` tweak [1]
      (2% adoption) resolves. Separate from the quality-loop workstream. [src: plan `atomic-popping-barto.md`]
- [ ] **Version-control the settings.json wiring.** The `memory-consulted` PostToolUse entry (and the
      other memory-hook entries) live only in the global `~/.claude/settings.json`, which is NOT in this
      repo. Decide: mirror into a tracked template (e.g. `settings.json.example`) so a clone reproduces
      the hook wiring. [src: handoff 5927821f]
- [x] **Precompact-hook state preservation.** vault-push captures session-end state; the PreCompact
      hook now ALSO writes a deterministic state snapshot (git working tree + active goal) alongside
      the transcript export, so a mid-session compaction doesn't lose the resume point. No GLM (hot-path
      free); rich synthesis stays vault-push's job. (2026-07-06)
- [ ] **Recall negative-case audit.** "Facts we missed" is unmeasured. Monthly: sample sessions → GLM
      "what durable facts?" → diff vs captured. Defer until utilization + approval signals prove useful.
      [src: plan `atomic-popping-barto.md`]

## Done (this workstream)

- [x] Q1 utilization hook — `memory-consulted-hook.sh` + settings wiring. (2026-07-06, `03e9561`)
- [x] Q2 hook-signal enrichment — infer `glm=ok|empty|err`; staleness `outcome:"error"`. (2026-07-06)
- [x] Q3 `/memory health` rollup + `--json`. (2026-07-06)
- [x] Q4 `/memory review` advisory tweaks. (2026-07-06)
- [x] Q5 end-to-end done-gate (promoted `commit-on-request`, approval 100%, staleness-floor fix). (2026-07-06)
- [x] S1 dialectic infer loop + S2 temporal invalidation. (2026-07-05, `e1f9956` `c928f36`)

## External / other repos

- [ ] **Unpushed `mparivahan-malware-analysis` session (16ae4c76)** — run `/vault-push` in that repo
      before it's lost. [src: SessionStart warning]
