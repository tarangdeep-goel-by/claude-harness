# OPEN_ITEMS — claude-harness

Project-level todos. Vault-push owns this file: add new, tick done, carry the rest.
Cross-cutting/ops todos live in the global `System/dashboards/Open Items.md` (not this file).

## Memory infra

- [ ] **S3 safe-archive (~19 files).** User-scoped to "safe archive only." Archive the ~19 pure-noise
      corpus files, then backfill high-value files onto the canonical schema so `/memory review` tweak [1]
      (2% adoption) resolves. Separate from the quality-loop workstream. [src: plan `atomic-popping-barto.md`]
- [ ] **Version-control the settings.json wiring.** The `memory-consulted` PostToolUse entry (and the
      other memory-hook entries) live only in the global `~/.claude/settings.json`, which is NOT in this
      repo. Decide: mirror into a tracked template (e.g. `settings.json.example`) so a clone reproduces
      the hook wiring. [src: handoff 5927821f]
- [ ] **Precompact-hook state preservation.** vault-push was upgraded to capture session-end state, but
      `precompact-hook.sh` was not — a mid-session compaction can drop detail. Add a state snapshot on
      PreCompact mirroring the vault-push handoff (lighter). [src: user, 2026-07-06]
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
