# Changelog

Adopter-facing changes to the harness. Versions are git-tagged (`vX.Y.Z`); the telemetry
`harness_version` column reports each machine's installed sha, so you can map the fleet to a release.
Update a machine with `./update.sh` (pulls + reconciles cleanly).

## 0.4.0 — 2026-07-25

Dev-focused public fork: data/product-coupled skills and content stripped;
portability + PII hardened so the harness installs clean on a fresh machine.

### Added
- **`drawio` + `humanizer`** skills (dev-focused, data-stack-agnostic).
- **`karpathy-guidelines`** shipped in-repo (was only available externally).
- 3 superseded hook scripts (`agent-awake`, `skill-log`, `skill-router`) restored to
  `vault-scripts/` for completeness (not wired in adopter settings — telemetry is consolidated
  via `tool-telemetry`).
- `install.sh` ports the safer `settings.json` takeover: backs up the user's file + migrates
  personal keys into `settings.local.json` before installing the harness copy (avoids the
  "existing settings with no harness hooks → silent inert" trap).

### Changed
- **Memory hooks** (`memory-consulted`, `memory-validate`, `memory-staleness`, `memory-infer`) +
  `memory_health.py` + `apply_memory.py`: hardcoded project path → **session-cwd-derived slug**
  (portable; matches Claude Code's per-project memory layout). Identical behavior for the
  umbrella-project cwd; correct per-project scoping elsewhere.
- **`install.sh`**: removed dead `SM_COUPLED_SKILLS` exclusion logic (those skills aren't in this fork).
- **`CLAUDE.md`**: rewritten as a clean, de-hardcoded operating-discipline doc (all workflow
  knowledge, no machine/personal specifics).
- `tests/hooks-smoke.sh`: `worktree-guard` deny test now sets `WORKTREE_GUARD_REPOS` (the guard is
  opt-in) so the deny path actually fires; SM fixture names neutralized.

### Removed (dev-focused fork — not data-stack-agnostic)
- `metabase-{query,instrumentation}`, `mixpanel-{analytics,chart-builder,instrumentation}`,
  `mp-to-ph-migration`, `sm-design-system`, `play-console`, `capture-journey`, `flutter-dev`
  (data/product-coupled).
- `template-overlay/` (entirely product-coupled).
- Product-specific refs scrubbed from README, make-vault-template, CONTINUITY, setup-qmd.

### Removed (privacy — no data leaves the machine)
- **Telemetry-upload pipeline** — `setup-telemetry-sink.sh`, `collate-telemetry.sh`,
  `infra-health/scripts/collect_telemetry.sh`, the daily `harness-telemetry-report` job, the
  update.sh onboarding-upload call, and the "Upload to maintainer" section of `/infra-health`.
  Local telemetry logging (`~/vault/logs/`) is unaffected — only the shared-Drive upload path
  is gone. `/infra-health` now states explicitly that all telemetry is local.
- **Google Drive project-doc utilities** — `vault-template/System/scripts/setup_gdrive.sh` +
  `upload_to_gdrive.sh`, and the `gog`/`rclone` dependency blocks in `bootstrap.sh`. The public
  release is Drive-free; bring your own if you want Drive integration.

## 0.1.0 — 2026-07-02

First versioned release — distribution-ready baseline.

### Added
- **`update.sh`** — clean update: pull + relink new skills/scripts, **prune** removed/data-coupled
  symlinks, refresh `settings.json` (backup first), sync vault infra, report new default daily-jobs.
- **Onboarding report** — `verify-setup.sh --json` emits a local install/verify report (stays on-machine).

### Changed
- **warm-start** now fails loud, not silent: accurate ERR-trap, no false FATALs on fresh vaults, a
  ⚠ degradation banner + real `outcome`/`brief_len` in telemetry (surfaced by `/infra-health`).
- **install.sh** — explicit owner vs adopter mode; adopters skip SM-coupled skills.
- **verify-setup.sh** — checks presence (not symlink) of `settings.json`; no longer false-flags
  adopter-skipped skills.

### Security
- Scrubbed personal Mixpanel test-account UUIDs from the capture-journey skill.
