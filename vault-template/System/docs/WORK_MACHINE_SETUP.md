# Work Machine Setup — Claude Code Infrastructure

Complete guide for bootstrapping the Claude Code hook system, QMD search engine, and Obsidian vault on a new work machine.

## Quick Start

```bash
chmod +x ~/Documents/vault-work/System/scripts/setup-work-machine.sh
~/Documents/vault-work/System/scripts/setup-work-machine.sh
```

The script is idempotent — safe to run multiple times.

---

## External tools, access & MCP (day-0 — beyond the harness)

`claude-harness/install.sh` symlinks the Claude infra; the **tools you actually work with** are set up
separately. A machine is only "at full level" once these are in place too.

| Tool / access | Setup | Used for |
|---|---|---|
| **Your data lib / venv** | Clone your analytics library under `~/code/` and install its venv | The backbone of all analysis work |
| **Google Drive** (optional) | `rclone config` → a `gdrive:` remote (user OAuth) | Drive read/write if your workflow needs it |
| **MCP connectors** | claude.ai **account-level** (come with the login) but must be **connected** in this client: **Slack, Linear**, or others. Local stdio: `tmux`, `qmd` (in harness `settings.json`). | Slack/Linear/other access from Claude |
| **Creds** | `~/code/.env`: your analytics API keys, DB credentials. `~/.claude/harness-telemetry.conf`: rclone remote + `OPERATOR` for telemetry. | API auth |
| **VPN** | up if required | Private database access |

> ⚠ **MCP tools load at SESSION START.** Connect a connector (Slack/Linear/PostHog) and then **restart
> Claude Code** — a server connected mid-session is invisible until the next start. (Learned the hard way.)

---

## Architecture Overview

The infrastructure consists of two vaults, Claude Code hooks, a search engine (QMD), and automation scripts.

### Two-Vault System

```
~/vault/                        Session Vault
├── sessions/                   Exported session transcripts (markdown)
├── daily/                      Daily journal entries
├── notes/                      Permanent knowledge notes
├── logs/                       Hook execution logs (hooks.jsonl, etc.)
├── scripts/                    All hook scripts + Python automation
└── learnings-queue.jsonl       Detected learnings from sessions

~/Documents/vault-work/         Knowledge Vault (Obsidian)
├── Daily/                      Daily capture notes
├── Notes/                      Project documentation
├── Categories/                 Bases views
├── Subjects/                   Bases views
├── Meta/                       Memory files, agent messages
└── System/
    ├── scripts/                Setup scripts, recorders
    ├── templates/              Obsidian templates
    ├── dashboards/             Obsidian dashboards
    ├── handoffs/               Session handoff notes
    └── docs/                   This file lives here
```

### Claude Code Config

```
~/.claude/
├── settings.json               Hooks config, permissions, MCP servers
├── CLAUDE.md                   Global instructions (all projects)
├── scripts/
│   └── warm-start.sh           SessionStart context injection
├── plans/                      Plan mode outputs
├── skills/                     Global skills — symlinked from claude-harness (recall, vault-push, …)
├── session-env/                Per-session environment files
└── projects/                   Per-project session data (managed by Claude)
```

---

## Hook System

Claude Code hooks fire at specific lifecycle events. Each hook is a shell script that reads JSON from stdin and optionally outputs JSON to stdout.

### Hook Lifecycle

```
SessionStart ──> [warm-start.sh]         Inject project context

SubagentStart ──> [subagent-context-hook.sh] Inject conventions into subagents

PreCompact ────> [precompact-hook.sh]     Export transcript before truncation

Stop ──────────> [completion-check-hook.sh] Scan for placeholder/stub code
                 [session-export-hook.sh]   Export session to markdown
                 [session-marker-hook.sh]   Liveness heartbeat + pushed flag
                 [tool-telemetry-hook.sh]   Skill/subagent telemetry → workflow.jsonl
```

### Hook Scripts Reference

| Script | Event | Purpose | Needs Path Updates |
|--------|-------|---------|-------------------|
| `precompact-hook.sh` | PreCompact | Exports full transcript before context compaction | No |
| `session-export-hook.sh` | Stop | Calls export-session.py to convert JSONL to markdown, then updates QMD | No |
| `session-marker-hook.sh` | SessionStart/Stop | Writes/updates the live-session marker (liveness heartbeat; `pushed` flag) | No |
| `subagent-context-hook.sh` | SubagentStart | Injects coding conventions and project CLAUDE.md hints | No |
| `warm-start.sh` | SessionStart | Gathers git state, project docs, QMD context. Located at `~/.claude/scripts/` | Check HOOKS_LOG, ERR_LOG |

### Python Scripts Reference

| Script | Called By | Purpose | Needs Updates |
|--------|-----------|---------|---------------|
| `export-session.py` | session-export-hook.sh, precompact-hook.sh | Converts Claude Code JSONL to clean markdown with YAML frontmatter | VAULT_SESSIONS path |
| `learning-detector.py` | session-export-hook.sh (background) | Regex-based detection of user corrections, decisions, discoveries | QUEUE_FILE path |

---

## QMD Search Engine

QMD provides hybrid search (BM25 + vector) over vault content. It indexes both vaults plus Claude plans.

### Collections (Work Machine)

| Collection | Path | Content |
|-----------|------|---------|
| `sessions` | `~/vault/sessions/` | Session transcripts |
| `daily` | `~/vault/daily/` | Daily journal entries |
| `vault-notes` | `~/vault/notes/` | Permanent knowledge |
| `work-daily` | `~/Documents/vault-work/Daily/` | Obsidian daily capture |
| `projects` | `~/Documents/vault-work/Notes/` | Project documentation |
| `handoffs` | `~/Documents/vault-work/System/handoffs/` | Session handoffs |
| `claude-plans` | `~/.claude/plans/` | Plan mode outputs |

### Usage

```bash
qmd query "topic" -c sessions       # Hybrid search (default, best)
qmd search "exact term" -c sessions # BM25 keyword only
qmd get qmd://sessions/file.md      # Read a full document
qmd ls sessions                     # List files in collection
qmd status                          # Index statistics
qmd update                          # Refresh file index
qmd embed                           # Generate/update embeddings
```

### Config Location

`~/.config/qmd/index.yml` — the setup script writes this automatically.

---

## Settings.json Structure

The `~/.claude/settings.json` file configures hooks, permissions, MCP servers, and Claude Code behavior.

```jsonc
{
  "permissions": {
    "allow": ["mcp__pencil"]           // Auto-allowed MCP tools
  },
  "hooks": {
    "PreToolUse": [...],               // Safety gates
    "PostToolUse": [...],              // Background automation
    "PermissionRequest": [...],        // Auto-allow rules
    "PreCompact": [...],               // Pre-truncation export
    "Stop": [...],                     // Session teardown
    "SubagentStart": [...],            // Subagent injection
    "SessionStart": [...]              // Environment setup
  },
  "syntaxHighlightingDisabled": false,
  "alwaysThinkingEnabled": true,
  "effortLevel": "high",
  "mcpServers": {
    "tmux": { ... }                    // local stdio MCP; account-level MCP (Slack/Linear/PostHog) connect in claude.ai
  }
}
```

---

## Skills

Claude Code custom skills are stored in `~/.claude/skills/`. Each skill is a directory with a markdown file that defines the skill's behavior.

### Required Skills

| Skill | Purpose |
|-------|---------|
| `vault-push` | Push session context to vault for future recall |
| `recall` | Search past sessions via QMD |
| `warm` | Warm-start context injection |
| `find-skills` | Skill discovery |
| `reflect` | Session reflection |
| `vault-audit` | Vault health and integrity checks |

### What It Does

1. Runs `qmd update && qmd embed` to index new sessions/notes
2. Cleans up stale lock files from `/tmp`
3. Rotates `hooks.jsonl` if it exceeds 10MB

### Manual Control

```bash
# Check status
launchctl list | grep claude

# Run manually
~/vault/scripts/daily-session-sync.sh

# Reload after editing plist
launchctl unload ~/Library/LaunchAgents/com.claude-harness.session-sync.plist
launchctl load ~/Library/LaunchAgents/com.claude-harness.session-sync.plist
```

---

## Vault LaunchAgents (daily-note + recorder plists)

`System/scripts/` ships two optional launchd plists:

| Plist | Purpose |
|-------|---------|
| `com.vault.daily-note.plist` | Creates today's Daily note at 08:00 |
| `com.vault.recorder.plist` | Keeps VaultRecorder running at login |

These plists use `__HOME__` as a placeholder because launchd does NOT expand `$HOME`.
Before loading them, substitute the placeholder with your actual home directory:

```bash
# Run once after cloning / copying the plists:
PLIST_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$PLIST_DIR"

for plist in \
  "com.vault.daily-note.plist" \
  "com.vault.recorder.plist"; do
  src="$HOME/Documents/vault-work/System/scripts/$plist"
  dst="$PLIST_DIR/$plist"
  sed "s|__HOME__|$HOME|g" "$src" > "$dst"
  launchctl load "$dst"
  echo "Loaded $plist"
done
```

> **Why `__HOME__` instead of `$HOME`?** launchd plist XML is not processed by a shell, so
> environment variable expansion like `$HOME` or `~` is silently ignored — the literal string
> would be used as the path, which doesn't exist. The `sed` substitution above bakes in the
> real path at install time.

---

## Path Updates After Copying

When copying scripts from the personal machine, some paths need updating. The key difference is the username/home directory.

### Find Hardcoded Paths

```bash
# Replace <prev-username> with the username from the source machine
grep -rn "/Users/<prev-username>" ~/vault/scripts/ ~/.claude/scripts/
```

### Key Paths to Verify

| Variable | Used In | Expected Value |
|----------|---------|---------------|
| `VAULT_SESSIONS` | export-session.py | `~/vault/sessions` |
| `PROJECTS_BASE` | session-export-hook.sh, precompact-hook.sh | `~/.claude/projects` |
| `HOOKS_LOG` | All hooks | `~/vault/logs/hooks.jsonl` |

---

## Troubleshooting

### Hooks Not Firing

1. Check `~/.claude/settings.json` is valid JSON: `python3 -m json.tool ~/.claude/settings.json`
2. Check scripts are executable: `ls -la ~/vault/scripts/`
3. Check hook logs: `tail -20 ~/vault/logs/hooks.jsonl`

### QMD Not Finding Content

1. Check config: `cat ~/.config/qmd/index.yml`
2. Check paths exist: verify all collection paths are populated
3. Re-index: `qmd update && qmd embed`
4. Check status: `qmd status`

### Session Export Failing

1. Check Python 3 is available: `which python3`
2. Check JSONL files exist: `ls ~/.claude/projects/*/`
3. Check export log: `grep session-export ~/vault/logs/hooks.jsonl | tail -5`

### Warm-Start Errors

1. Check error log: `cat ~/vault/logs/warm-start-errors.log`
2. Ensure jq is installed: `which jq`
3. Test manually: `echo '{"session_id":"test","cwd":"/tmp","source":"startup"}' | ~/.claude/scripts/warm-start.sh`
