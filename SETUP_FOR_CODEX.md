# SETUP_FOR_CODEX — Codex runbook for the inter-platform harness

Audience: you, Codex, on a machine that should use this harness without migrating away from Claude
Code. Claude Code remains supported; this runbook adds Codex as a first-class surface.

Kick-off line the user can paste into Codex:

```text
Read SETUP_FOR_CODEX.md and get Codex using this harness. Walk me through each step and verify it.
```

Related docs: `README.md` for the full harness overview, `CLAUDE.md` for the Claude Code contract,
`AGENTS.md` for the Codex contract, and `SETUP_FOR_CLAUDE.md` for the existing Claude setup path.

## Current State to Preserve

- Primary parent workspace: `/Users/tarang/Documents/Projects`.
- Shared markdown session archive: `/Users/tarang/vault/sessions`.
- Historical Claude markdown exports at inventory time: 2,371 files, including 2,338 with Claude
  models.
- Current raw Claude Code cache at inventory time: `/Users/tarang/.claude/projects`, with 43
  top-level JSONL sessions and 25 subagent JSONL sessions.
- Codex raw sessions: `/Users/tarang/.codex/sessions`.
- Codex markdown export: Stop/finalization hook or manual `export_codex_session.py` into
  `/Users/tarang/vault/sessions`.
- QMD is required for recall and may be in repair; verify with `qmd status` before relying on it.

## Ordered Runbook

### 0. Work From the Primary Projects Root

Durable repo work should live under `/Users/tarang/Documents/Projects`:

```bash
mkdir -p /Users/tarang/Documents/Projects
cd /Users/tarang/Documents/Projects/claude-harness
git status --short
```

If you are working in a task worktree, confirm it is a worktree and not the main checkout:

```bash
git worktree list
git rev-parse --abbrev-ref HEAD
pwd
```

### 1. Install the Shared Source Assets

Run the existing harness installer for the shared Claude/vault assets. This keeps the current
Claude setup intact and links the common vault scripts used by both surfaces:

```bash
./install.sh
./bootstrap.sh
```

Do not copy secrets. Keep machine-specific secrets in the existing local secret locations described
by `SECRETS.example.md`; never place them in this repo or in Codex project docs.

Verify shared assets:

```bash
ls -la /Users/tarang/vault/scripts/session-export-hook.sh
ls -la /Users/tarang/vault/scripts/precompact-hook.sh
ls -la /Users/tarang/vault/scripts/session-marker-hook.sh
```

### 2. Link or Copy Codex-Specific Assets

Install the Codex-side assets from this repo. The port keeps Codex assets separate from `claude/**`
so Claude Code continues to work unchanged:

```bash
./install-codex.sh
```

Expected source assets:

```bash
test -f codex/hooks.json
test -f codex/config.example.toml
test -f codex/scripts/codex_hook_adapter.py
test -f codex/scripts/codex_warm_start.sh
test -f codex/scripts/export_codex_session.py
test -f codex/scripts/finalize_session.sh
test -f codex/scripts/codex_hooks_doctor.py
```

Expected installed assets:

```bash
test -f /Users/tarang/.codex/hooks.json
test -L /Users/tarang/.codex/scripts/codex_hook_adapter.py
test -L /Users/tarang/.codex/scripts/codex_warm_start.sh
test -L /Users/tarang/.codex/scripts/export_codex_session.py
test -L /Users/tarang/.codex/scripts/finalize_session.sh
```

Merge selected settings from `codex/config.example.toml` into `/Users/tarang/.codex/config.toml`
by hand. Verify the feature flag:

```bash
rg -n "codex_hooks\\s*=\\s*true" /Users/tarang/.codex/config.toml
```

Prefer symlinks for repo-owned scripts and copies only for Codex-owned config files. `hooks.json`
is rendered and copied because Codex owns the live config file. The repo template keeps
`~/.codex/...` paths for portability; `install-codex.sh` expands them to the local absolute
`/Users/tarang/.codex/...` path during install.

Do not copy:

- API keys.
- OAuth tokens.
- Cookies.
- Raw session JSONL files.
- `~/.claude/settings.local.json`.
- Any `.env`, `*secret*`, `*auth*`, `.pem`, or `.key` file.

### 3. Verify Codex Hook Wiring

Codex hook wiring should provide the same continuity outcomes as Claude:

- session start or finalization identifies the active project;
- Codex session markdown lands in `/Users/tarang/vault/sessions`;
- QMD can index the exported markdown;
- project `AGENTS.md` and `System/handoffs/RESUME.md` are visible during resume.

Verify `codex_hooks` and the installed hook manifest:

```bash
python3 /Users/tarang/.codex/scripts/codex_hooks_doctor.py
python3 -m json.tool /Users/tarang/.codex/hooks.json >/dev/null
rg -n "codex_hook_adapter|SessionStart|UserPromptSubmit|Stop" /Users/tarang/.codex/hooks.json
rg -n "codex_hooks\\s*=\\s*true" /Users/tarang/.codex/config.toml
```

If the doctor or feature-flag check fails, Codex is not yet wired for harness finalization. Stop
and install the Codex-side assets before claiming setup is complete.

### 4. Verify QMD Recall

QMD is the recall spine. It must see `/Users/tarang/vault/sessions`:

```bash
qmd status
qmd collection list
qmd query "claude harness codex port" -c sessions
```

If `qmd status` fails, do not treat recall as working. Run the QMD repair or setup path before
depending on prior-session search.

### 5. Verify Codex Session Export

Create or use a small Codex session with a unique marker, then finalize/export it and verify a
markdown file appears in the shared archive:

```bash
MARKER="CODEX_HARNESS_EXPORT_$(date +%Y%m%d%H%M%S)"
printf '%s\n' "$MARKER"
find /Users/tarang/vault/sessions -maxdepth 1 -type f -name '*.md' -mtime -1 -print
rg -n "$MARKER|Codex" /Users/tarang/vault/sessions
```

Manual fallback when the hook has not run:

```bash
python3 /Users/tarang/.codex/scripts/export_codex_session.py 2>&1 | head -1
```

The usage output should show `export_codex_session.py <session.jsonl> [output.md]`. Use the
current session JSONL from `/Users/tarang/.codex/sessions`, then run:

```bash
qmd update
qmd embed
qmd query "$MARKER" -c sessions
```

By default, Codex finalization does not mutate `/Users/tarang/vault/daily`,
`/Users/tarang/vault/notes`, or `/Users/tarang/.codex/memories`. The optional
`memory_sync_codex.py` path is present but gated behind `CODEX_HARNESS_MEMORY_SYNC=1` until Codex
semantic-memory policy is deliberately enabled.

For history mining and deep reads:

```bash
./catalog-codex-sessions.sh 30
./read-codex-session.sh <session-id-or-jsonl-path>
```

These are Codex-native counterparts to `catalog-sessions.sh` and `read-session.sh`. They read
`/Users/tarang/.codex/sessions` directly and do not touch Claude files.

### 6. Verify Project Resume Scaffolding

Every durable project should expose the files Codex needs for resume:

```bash
test -f AGENTS.md
test -f System/handoffs/RESUME.md
find Notes -maxdepth 3 -type f \( -name PROJECT_LOG.md -o -name OPEN_ITEMS.md -o -name '*.md' \) | head
```

Codex resume order:

1. Read project `AGENTS.md`.
2. Read `System/handoffs/RESUME.md`.
3. Read `Notes/<repo-name>/PROJECT_LOG.md` and open items when relevant.
4. Query `~/vault/sessions` through QMD for deeper history.

### 7. Final Setup Proof

Report these checks together:

```bash
pwd
git worktree list
test -f AGENTS.md
test -f CLAUDE.md
qmd status
rg -n "codex_hooks\\s*=\\s*true" /Users/tarang/.codex/config.toml
python3 /Users/tarang/.codex/scripts/codex_hooks_doctor.py
find /Users/tarang/vault/sessions -maxdepth 1 -type f -name '*.md' | wc -l
```

A complete Codex setup means:

- Claude Code still has `CLAUDE.md`, `claude/**`, and its hooks/skills.
- Codex has `AGENTS.md` and Codex hook/finalization wiring.
- `/Users/tarang/Documents/Projects` remains the primary workspace parent.
- `/Users/tarang/vault/sessions` is the shared history archive.
- QMD can search that archive.
- Project resume starts from `System/handoffs/RESUME.md`.
