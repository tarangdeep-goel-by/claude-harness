# SETUP_FOR_CLAUDE — drive a new adopter from clone → verified working harness

**Audience: you, Claude, on a freshly-installed machine.** A human just cloned this repo (or is
about to). Your job is to **shepherd them through setup and verify each step actually worked** —
don't assume, check. Go top to bottom; at each step run the check, report ✓/⚠, and only move on
when it's green or they choose to skip.

> Kick-off line the user pastes: *"Read SETUP_FOR_CLAUDE.md and get my machine fully set up — walk
> me through each step and verify it."*

Related docs (read when a step points there): `README.md` (human overview), `SECRETS.example.md`
(what creds go where), `ADOPT_FROM_HISTORY.md` (the payoff back-fill), and — once running —
`CLAUDE.md` (the operating discipline).

---

## Architecture — understand before you start (so you can debug)

**This repo is the single source of truth.** `install.sh` symlinks FROM the repo INTO the live
config, so editing repo files updates the live setup with **zero drift** (and `./update.sh` pulls
+ reconciles). Nothing is copied except `settings.json` (Claude Code owns that file).

| Repo path | Live target | How |
|---|---|---|
| `claude/skills/<name>/` | `~/.claude/skills/<name>` | symlink per skill |
| `vault-scripts/*.sh` | `~/vault/scripts/<name>` | symlink per hook |
| `claude/scripts/warm-start.sh` | `~/.claude/scripts/warm-start.sh` | symlink |
| `claude/settings.adopter.json` | `~/.claude/settings.json` | **copied** (refreshed by `./update.sh`) |
| `vault-template/` | `~/Documents/vault-work` | **seeded once** (never clobbers existing) |

Machine-specific config belongs in `~/.claude/settings.local.json` (Claude Code merges it over
`settings.json`; updates never touch it).

---

## The ordered runbook

**0 · Clone (if not already).**
```bash
git clone <your-fork-url> ~/Documents/Projects/claude-harness
cd ~/Documents/Projects/claude-harness
```

**1 · Engine installed.** Confirm `install.sh` ran and symlinked the engine.
```bash
./install.sh               # idempotent — safe to re-run; adopter mode by default (--owner for the maintainer)
./verify-setup.sh          # engine block should be ✓ (settings present, skills symlinked)
ls -la ~/.claude/skills/recall ~/vault/scripts/file-guard-hook.sh   # both → symlinks into this repo
```

**2 · Dependencies.** `bootstrap.sh` installs what the harness assumes.
```bash
./bootstrap.sh             # required: jq, python3. best-effort: gh, qmd
```
Re-run `verify-setup.sh` → the `dependencies` block should go ✓. Notes:
- **`qmd`** (hybrid search powering `/recall`, the task-start **skill-retrieval** hook, + vault
  indexing) most often needs manual install (Node ≥22 or Bun), then `qmd update && qmd embed`.
  Without it `/recall` still works via direct file reads and skill-retrieval no-ops — only search
  degrades.
- **memory-infer** (auto-suggests durable memories at session end) needs a z.ai GLM-4.7 bearer
  key at `~/.config/claude-glm/key`. Without it the hook no-ops (non-blocking).

**3 · Secrets.** `cp SECRETS.example.md SECRETS.md` and help the user place their creds. The
harness **core needs none**; only optional integrations do. Never invent values — point them at
where each comes from. `.gitignore` already guards `*.env`, `*secret*`, `*auth*.json`, `*.pem`,
`*.key`.

**4 · (Optional) Official plugins — `/code-review`, `/verify`, `/simplify`.** These are **not in
this repo** (Anthropic's official plugins). From Claude Code:
```
/plugin install claude-plugins-official
```
Enable the ones you want. `CLAUDE.md` references `/code-review` + `/verify`; install this
marketplace to make them available.

**5 · Telemetry is local (privacy).** All harness telemetry stays on this machine under
`~/vault/logs/` (see `/infra-health`). **Nothing is uploaded** — no Drive, no shared sink, no
maintainer report. This public release ships no log-upload machinery by design.

**6 · MCP + restart.** Connect account-level MCP connectors (Slack / Linear / etc.) in claude.ai,
then **restart Claude Code** so hooks + MCP load (hooks load at session start).

**7 · Verify the whole thing.** Re-run and read every line to the user:
```bash
./verify-setup.sh          # remaining ⚠ are the user's to finish (secrets, /onboard)
./tests/hooks-smoke.sh     # fires every hook against a representative event; must end "PASSED"
```

**8 · Onboard memory.** In the seeded vault, run `/onboard` to fill `Meta/memory.md` (who they
are, projects, preferences). Empty memory = a much weaker warm-start.

**9 · The payoff — back-fill from history.** This justifies the setup effort: follow
`ADOPT_FROM_HISTORY.md` to reconstruct the last 30 days (Claude Code sessions and/or claude.ai /
desktop-app chats via data export) into a populated, `/recall`-able vault. Show what you rebuilt,
then demo a live `/recall`.

---

## Using it — the workflow (tell the user once set up)

Point Claude at **`CLAUDE.md`** (the operating discipline). For any dev task it mandates:
`workflow-engine` skill FIRST → `task-triage` → `karpathy-guidelines` → do the work
(`/code-review` on the diff) → `debug-escalation` if it breaks → `done-gate` before claiming done
→ `/vault-push` at session end. Key skills: `/recall`, `/vault-push`, `/memory health`,
`/infra-health`, `/reflect`. Hooks fire automatically; telemetry lands in `~/vault/logs/`.

---

## Extending (drift-free by design)

- **Add a skill:** `claude/skills/<name>/SKILL.md`, then re-run `./install.sh` (or hand-symlink).
- **Add a hook:** `vault-scripts/<name>.sh` + wire into `claude/settings.adopter.json`, re-run
  `./install.sh`. Both are repo-tracked (source of truth), so commits capture the change.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Hooks not firing | Restart Claude Code; confirm `jq '.hooks\|keys' ~/.claude/settings.json` is populated; run `./tests/hooks-smoke.sh`. |
| `/recall` search empty | `qmd` missing/unindexed → `qmd update && qmd embed`. File-read recall works without it. |
| `memory-infer` no candidates | Missing `~/.config/claude-glm/key` (z.ai). No-ops safely without it. |
| `settings.json` overwritten | Personal keys migrated to `~/.claude/settings.local.json` — machine config goes there. |

---

## Staying current (tell the user once)

- **Updates:** `cd <this repo> && ./update.sh` — pulls + reconciles (relinks new skills, prunes
  removed, refreshes settings with backup, syncs vault infra). warm-start nudges *"N commits
  behind — run ./update.sh"* when stale.
- **Why this matters:** the engine is symlinked from this one repo, so an update reaches this
  machine on the next `./update.sh` — one source of truth, no drift.
