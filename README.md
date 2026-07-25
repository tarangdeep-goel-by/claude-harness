# claude-harness

A complete, shareable Claude Code working environment — the hooks, skills, session-continuity
scripts, settings, **and** a ready-to-fill PM knowledge-vault scaffold. Clone + `./install.sh` and a
fresh machine has the whole system: the engine *and* an empty vault to put your own knowledge into.

> Self-contained: the global engine (hooks + skills) **and** the project vault scaffold
> (`vault-template/`) ship in one repo — `clone + ./install.sh` stands up the full system.

## New machine / new teammate

> **Prefer to have Claude drive it?** After `install.sh`, open Claude Code and paste: *"Read
> `SETUP_FOR_CLAUDE.md` and get my machine fully set up — walk me through each step and verify it."*
> It's the ordered, self-verifying runbook (bootstrap → secrets → telemetry → verify → onboard →
> history back-fill). The manual steps below are the same thing by hand.

```bash
git clone <this-repo> ~/code/claude-harness
cd ~/code/claude-harness
./install.sh                 # symlinks the engine into ~/.claude + ~/vault/scripts,
                             #   AND seeds a vault from vault-template/ (only if none exists)
./bootstrap.sh               # deps: jq, python3; checks qmd / gh
bash ~/Documents/vault-work/System/scripts/setup-work-machine.sh   # qmd index, transcription models, launchd
# copy secrets into ~/.claude + ~/code/.env  (see SECRETS.example.md)
# connect account-level MCP (Slack/Linear/PostHog) in claude.ai, then restart Claude Code
./verify-setup.sh            # run LAST (after setup-work-machine builds the qmd index); flags silent gaps
# open ~/Documents/vault-work in Obsidian → /onboard (fill Meta/memory.md) → /start-work
```

Steps are ordered: `install` wires the engine + seeds the vault; `bootstrap` installs deps;
`setup-work-machine.sh` builds the qmd index + transcription models + the daily-sync launchd agent;
then secrets + MCP; `verify-setup.sh` last (so its qmd-index check passes). Full external-tool
detail (MCP, VPN) lives in the seeded
`vault-template/System/docs/WORK_MACHINE_SETUP.md`.

> **qmd is required for `/recall` and warm-start context.** Install it (source: `github.com/tobi/qmd`):
> `npm install -g @tobilu/qmd` (or `bun install -g @tobilu/qmd`). Needs Node ≥22 or Bun; on macOS
> also `brew install sqlite`. First use auto-downloads ~2 GB of on-device models to `~/.cache/qmd`.
> Then `qmd update && qmd embed` to build the index. Without qmd, `/recall` and warm-start degrade
> gracefully — they no-op rather than crash, but vault search is disabled.

## Already have Claude history? Back-fill from it (the fast win)

Coming from the **Claude desktop app / claude.ai chats** (most people) or from **Claude Code**? Don't
start empty — mine your own history into a populated vault so the onboarding pays off immediately:

```bash
# A) Claude Code (local):
./catalog-sessions.sh 30                       # map recent sessions: title + opening goal

# B) Claude desktop app / claude.ai (server-side → get the data export):
#    claude.ai → Settings → Privacy → Export data → email zip → unzip → conversations.json
./catalog-chats.sh conversations.json 30       # map recent chats the same way

# then, in the seeded vault, tell Claude:
#   "Read ADOPT_FROM_HISTORY.md and build my vault from my last 30 days — projects, KBs, arcs,
#    decisions, people, memory. Show me what you reconstructed."
```

It clusters sessions **and** chats into real projects, deep-reads the high-signal ones
(`read-session.sh` / `read-chat.sh` strip the noise to plain prose), and **builds**
`Notes/<project>/` (README, PROJECT_LOG, PROJECT_ARC, KNOWLEDGE_BASE) + `decisions/` ADRs +
People/Glossary + memory + Open Items — then proves it with live `/recall`. Full playbook:
**`ADOPT_FROM_HISTORY.md`**.

In the seeded vault, open `CLAUDE.md` first — it carries an **adapt checklist** (set your product
area, run `/onboard`, add your own data-stack skills).

`install.sh --vault ~/Documents/<name>` seeds the vault somewhere else. **It never overwrites an
existing vault** — if one is already there, the scaffold is skipped and only the engine is (re)linked.

## What's here

```
claude/                       the GLOBAL half → ~/.claude
  settings.json                 hooks, MCP servers, permissions
  scripts/warm-start.sh         SessionStart context injection
  skills/<name>/                global skills (work types + continuity)
vault-scripts/*.sh *.py       hooks + automation → ~/vault/scripts (Stop/PreCompact/SessionStart/…)
vault-template/               the PROJECT half → seeded into a new vault by install.sh
  CLAUDE.md                     operating manual (adapt the domain bits)
  .claude/{skills,agents,commands}   capture skills + librarian + slash commands
  System/{templates,scripts,docs}    doc templates, generic infra scripts, architecture docs
  System/{dashboards,daily-jobs.yaml,handoffs}   empty ledgers + example jobs
  Categories/ Subjects/         cross-cutting Bases view definitions
  Daily/ Notes/ People/ Glossary/ Meta/   empty taxonomy + READMEs (no knowledge)
install.sh                    symlink deployer + vault seeder (idempotent)
bootstrap.sh                  dependency installer
verify-setup.sh               post-install health check (symlinks/deps/qmd/vault/creds)
make-vault-template.sh        regenerate vault-template/ from a live vault (knowledge-stripped)
catalog-sessions.sh           map your last N days of Claude Code sessions (titles + goals)
read-session.sh               print one Claude Code session's conversation, tool-noise stripped
catalog-chats.sh              map your claude.ai/desktop chats from a data export (conversations.json)
read-chat.sh                  print one claude.ai chat's conversation
ADOPT_FROM_HISTORY.md         playbook: build a populated vault from Claude Code sessions AND chats
SECRETS.md                    what to copy in by hand (never committed)
```

### Skills
- **Global** (`claude/skills/` → `~/.claude/skills/`): the workflow-engine family
  (`workflow-engine`, `task-triage`, `karpathy-guidelines`, `debug-escalation`, `done-gate`,
  `review-merge`) + `recall`, `vault-push` (session bookends) + `memory`, `reflect`, `stats`,
  `vault-audit`, `infra-health`, `find-skills`, `drawio`, `humanizer`, `warm`. 17 skills, all
  symlinked from this repo (drift-free).
- **Vault** (`vault-template/.claude/skills/` → seeded into the vault): `scribe`, `transcriber`,
  `sorter`, `compiler`, `export` (capture). Agent: `librarian`. Plus the slash commands.
- All shipped skills are **dev-focused and data-stack-agnostic**. Bring your own product/analytics
  skills under your vault's `.claude/skills/` as needed.

### Telemetry (local — nothing leaves your machine)
Every hook logs to `~/vault/logs/hooks.jsonl`; **skill + subagent** invocations are captured by
`tool-telemetry-hook.sh` → `~/vault/logs/workflow.jsonl`. The memory hooks (`memory-consulted`,
`memory-validate`, `memory-staleness`, `memory-infer`) track memory quality. Session liveness →
`active-sessions/`. Run **`/infra-health`** for the rollup (per-hook count/failure/p50–p95, skill
frequency, job freshness, unpushed-session rate). **All telemetry stays local** — this harness ships
no log-upload machinery. (`/stats` is separate — cost/token usage.)

### Hook scripts (`vault-scripts/`)
- `session-marker-hook.sh` — live/parallel session heartbeats.
- `warm-start.sh` (in `claude/scripts/`) — SessionStart project intelligence.
- `session-export-hook.sh` / `precompact-hook.sh` — export transcripts → `~/vault/sessions` → qmd.
- `auto-checkpoint-hook.sh` — git-stash safety net. `completion-check-hook.sh` — placeholder gate.
- `learning-detector.py` — learnings extraction (feeds the `reflect` skill).
- `file-guard-hook.sh`, `block-dangerous-hook.sh`, `allow-python-hook.sh` — safety/permission gates.

## Day-0 tools & access (beyond `install.sh`)

The harness wires the Claude infra + vault; **your data tools are set up separately.** A machine is
only "at full level" once these are in place:

- **Your data library / venv** — whatever your analytics stack uses (a Python lib, dbt project,
  BigQuery client, etc.). Wire it into `~/code/`.
- **MCP connectors** (claude.ai account-level — must be **connected** in this client): Slack, Linear,
  or other integrations. Add local stdio servers (e.g. `tmux`, `qmd`) to `settings.json` if you want them. ⚠ Connect, then **restart**.
- **Creds / access** (`~/code/.env` + `~/.claude`, see `SECRETS.example.md`): your analytics API keys,
  database credentials, and any API keys your data tools need.

Full detail: `vault-template/System/docs/WORK_MACHINE_SETUP.md`; the paradigm:
`vault-template/System/docs/HOW_THIS_SYSTEM_WORKS.md`.

## Maintaining the harness

- **Engine** (`claude/`, `vault-scripts/`): `install.sh` **symlinks** these, so editing a live file
  edits the repo — single source of truth. Re-run anytime; idempotent.
- **Vault scaffold** (`vault-template/`): NOT symlinked (a new vault gets its own copy). When you
  evolve your skills/templates/`CLAUDE.md` in a real vault, run **`./make-vault-template.sh`** to
  regenerate `vault-template/` (knowledge-stripped, by allowlist), then commit. That's how the
  shareable harness stays current without leaking knowledge.

> ⚠ `settings.json` is **copied** (not symlinked) by `install.sh` — Claude Code owns that file. If a
> tool overwrites it, re-run `./install.sh` to re-seed the harness hooks (your personal keys live in
> `~/.claude/settings.local.json`, which updates never touch).

## Two vaults (don't conflate them)
- **`~/Documents/vault-work/`** — the **knowledge vault** (Obsidian, git-tracked, your own repo).
  Notes, projects, decisions, daily captures. Seeded from `vault-template/` on first install; then
  it's yours.
- **`~/vault/`** — the **harness runtime** (machine-local, never committed). Hook scripts (symlinks
  to this repo), telemetry logs, raw session exports, the learnings queue. Created by `install.sh`.
- Flow: raw machine output → `~/vault` → distilled by you → `~/Documents/vault-work`.

## Data (never committed)
`~/vault/{sessions,daily,notes,logs}`, `~/.claude/{projects,history.jsonl,…}`, caches, and all
secrets are machine-local. This repo carries only the reproducible harness + the empty scaffold.

## License
MIT — see [LICENSE](LICENSE). The bundled `humanizer` skill carries its own MIT License.
