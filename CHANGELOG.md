# Changelog

Adopter-facing changes to the harness. Versions are git-tagged (`vX.Y.Z`); the telemetry
`harness_version` column reports each machine's installed sha, so you can map the fleet to a release.
Update a machine with `./update.sh` (pulls + reconciles cleanly).

## 0.1.0 — 2026-07-02

First versioned release — distribution-ready baseline.

### Added
- **`report-telemetry` skill** — on-demand/scheduled upload of detailed logs (`.tar.gz`) + a summary
  row to a shared Google Drive folder via **rclone** (no Google Cloud client needed). Credential
  shapes redacted; all other detail kept. Carries `operator` (who), `install_id`, `harness_version`
  (sha + dirty + commit date), OS.
- **`setup-telemetry-sink.sh`** — maintainer creates the Drive folder (owns it → guaranteed access).
- **`collate-telemetry.sh`** — folds per-report summaries into one append-only index CSV.
- **`update.sh`** — clean update: pull + relink new skills/scripts, **prune** removed/SM-coupled
  symlinks, refresh `settings.json` (backup first), sync vault infra, report new default daily-jobs.
- **Onboarding report** — `verify-setup.sh --json` + upload, so the maintainer sees whether each
  machine installed cleanly.
- Daily `harness-telemetry-report` job seeded in the vault template (`--if-configured`, no-op until set).

### Changed
- **warm-start** now fails loud, not silent: accurate ERR-trap, no false FATALs on fresh vaults, a
  ⚠ degradation banner + real `outcome`/`brief_len` in telemetry (surfaced by `/infra-health`).
- **install.sh** — explicit owner vs adopter mode; adopters skip SM-coupled skills.
- **verify-setup.sh** — checks presence (not symlink) of `settings.json`; no longer false-flags
  adopter-skipped skills.

### Security
- Scrubbed personal Mixpanel test-account UUIDs from the capture-journey skill.
