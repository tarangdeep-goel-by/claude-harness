# SETUP_FOR_CLAUDE — drive a new adopter from clone → verified working harness

**Audience: you, Claude, on a freshly-installed machine.** A human just cloned this repo and ran
(or is about to run) `install.sh`. Your job is to **shepherd them through the remaining setup and
verify each step actually worked** — don't assume, check. Go top to bottom; at each step run the
check, report ✓/⚠ to the user, and only move on when it's green or they choose to skip.

> Kick-off the user pastes: *"Read SETUP_FOR_CLAUDE.md and get my machine fully set up — walk me
> through each step and verify it."*

Related docs (read when a step points there): `README.md` (human overview), `SECRETS.md` (what
creds go where), `ADOPT_FROM_HISTORY.md` (the payoff back-fill), and — once running — the vault's
`System/docs/HOW_THIS_SYSTEM_WORKS.md` + `CLAUDE.md` (how to operate).

---

## The ordered runbook

**1 · Engine installed.** Confirm `install.sh` ran and symlinked the engine.
```bash
./verify-setup.sh          # engine section should be ✓ (settings present, skills symlinked)
```
If skills/settings are missing → `./install.sh` (adopter mode by default; `--owner` only for the maintainer).

**2 · Dependencies.** `bootstrap.sh` installs what the harness assumes.
```bash
./bootstrap.sh             # jq, qmd, gh, gog, rclone
```
Re-run `verify-setup.sh` → the `dependencies` block should go ✓. `qmd` is the one that most often
needs manual love (Node ≥22 / Bun; then `qmd update && qmd embed`) — recall + warm-start context
depend on it.

**3 · Secrets.** Read `SECRETS.md` and help the user place their creds. The harness *core* needs
none; only data-stack skills do. Never invent values — point them at where each comes from.

**4 · Telemetry + updates (rclone).** So the maintainer can see this machine's health and give
directed fixes:
```bash
rclone config             # create a 'gdrive' drive remote — rclone's own OAuth, no Cloud key
cat >> ~/.claude/harness-telemetry.conf <<'CONF'
RCLONE_REMOTE=gdrive
OPERATOR=your.name@company.com     # who this machine is — REQUIRED for directed fixes
CONF
```
(The shared `DRIVE_FOLDER` ships as a default; only set it if the maintainer gives you a different one.)
Then a first report so the maintainer knows you're online:
```bash
bash ~/.claude/skills/infra-health/scripts/collect_telemetry.sh --dry-run   # preview what's sent
bash ~/.claude/skills/infra-health/scripts/collect_telemetry.sh             # upload
```

**5 · MCP + restart.** Connect account-level MCP (Slack / Linear / PostHog / Drive) in claude.ai,
then **restart Claude Code** so hooks + MCP load.

**6 · Verify the whole thing.** Re-run and read every line to the user:
```bash
./verify-setup.sh          # remaining ⚠ are the user's to finish (secrets, /onboard)
```
This also auto-emits an onboarding report to the sink on `update.sh` runs, so the maintainer sees
whether this machine came up cleanly.

**7 · Onboard memory.** In the seeded vault, run `/onboard` to fill `Meta/memory.md` (who they are,
team, product). Empty memory = a much weaker warm-start.

**8 · The payoff — back-fill from history.** This is the moment that justifies the setup effort:
follow `ADOPT_FROM_HISTORY.md` to reconstruct their last 30 days (Claude Code sessions **and/or**
claude.ai / desktop-app chats via a data export) into a populated, `/recall`-able vault. Show them
what you rebuilt, then demo a live `/recall`.

---

## Staying current (tell the user once)

- **Get updates:** `cd <this repo> && ./update.sh` — pulls + reconciles cleanly (relinks new skills,
  prunes removed ones, refreshes settings, syncs vault infra). warm-start will nudge *"N commits
  behind — run ./update.sh"* when they're behind, so they don't drift.
- **Why this matters:** the engine is **symlinked from this one repo**, so an update the maintainer
  pushes reaches every machine on the next `./update.sh` — one source of truth. Machine-specific
  settings belong in `~/.claude/settings.local.json` (never clobbered by updates).
