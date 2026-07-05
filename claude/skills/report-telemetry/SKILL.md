---
name: report-telemetry
description: "Upload this machine's harness telemetry logs to a shared Google Drive folder, on demand, so the harness maintainer can debug errors you hit. Use when the user says \"send/upload/report telemetry\", \"share my harness logs\", \"report this error to the maintainer\", \"send my logs for debugging\", or is asked by the maintainer to send their telemetry. Uploads via rclone (the user's own gdrive: remote) — no shared secret, no Google Cloud client to set up."
---

# /report-telemetry — Ship harness logs to Drive for debugging

Bundles the local harness telemetry under `~/vault/logs/`, redacts obvious credentials
(everything else stays **detailed**), and reports it to a shared Google Drive folder via
**rclone** (the user's own `gdrive:` remote — rclone's built-in OAuth, no Cloud key needed).
**Two files per report, neither ever overwrites a prior one** (both timestamped):

1. a `.tar.gz` of the detailed logs — for debugging
2. a `.summary.json` one-line summary — the maintainer's `collate-telemetry.sh` folds all of
   these into one index CSV (the "same table"), regenerated as the folder grows

Runs **on demand** (this skill) or **periodically** (a scheduled job — see below). Append-only:
periodic runs accrue files, never clobber.

## One-time setup

**Maintainer (once):** create the shared folder in your own Drive (so you own it → guaranteed
access), then share it Editor with the team (the one manual step — rclone can't set sharing):
```bash
~/code/claude-harness/setup-telemetry-sink.sh          # creates folder, prints its ID + config
# → open the printed Drive link → Share → team as Editor
```

**Each machine:** an rclone drive remote + the folder id:
```bash
rclone config      # n → name it 'gdrive' → storage 'drive' → browser OAuth (no Cloud key)
cat >> ~/.claude/harness-telemetry.conf <<'CONF'
DRIVE_FOLDER=<folder-id>
RCLONE_REMOTE=gdrive
OPERATOR=your.name@company.com
CONF
```

## Run it

Always preview first, show the user what will be sent, then upload:
```bash
# 1. Preview — bundles + redacts, prints the summary + file list, does NOT upload
bash ~/.claude/skills/report-telemetry/scripts/collect_telemetry.sh --dry-run

# 2. Upload (after the user confirms)
bash ~/.claude/skills/report-telemetry/scripts/collect_telemetry.sh
```
Report back the `install_id` — the maintainer needs it to find this machine's rows/bundles.

## What gets sent (be transparent with the user)

- **Included, detailed:** every log under `~/vault/logs/` — `hooks.jsonl` (hook health,
  outcomes, exit codes, durations), `warm-start-errors.log`, `events.jsonl` / `skills.jsonl`
  / `routing.jsonl` / `workflow.jsonl` (skill + subagent behavior), `daily-jobs.jsonl`,
  and the `active-sessions/` markers. Paths, event names, session ids, timings, and errors
  are **preserved** — that's what makes them debuggable.
- **A summary + manifest:** a random `install_id` (no name/email), harness git sha, OS, a
  one-way hash of the hostname (for grouping only), the timestamp, and error counts.
- **Redacted:** credential-shaped strings (`sk-…`, `xox…`, `ghp_…`, `AIza…`, `Bearer …`,
  `token=/password=/secret=…`) → `[REDACTED]` as a safety net.
- **Never sent:** prompts, conversation transcripts, file contents, vault notes. Only the
  telemetry logs. The bundle is built from a temp copy; your real logs are untouched.

## Periodic reporting (optional)

The script is non-interactive, so schedule it — add to the vault's
`System/scripts/run-daily-jobs.sh` (once/day) or a cron entry:
```bash
bash ~/.claude/skills/report-telemetry/scripts/collect_telemetry.sh   # reads config, no prompts
```
Each run drops a new timestamped bundle + summary — **nothing is overwritten**, so the folder
is a full history per machine.

## Notes

- Upload uses the user's own `gdrive:` remote via rclone's `root_folder_id` connection-string,
  writing straight into the maintainer's shared folder — no credential is baked into the harness.
- rclone does files only (it can't append to a Sheet), so the "same table" is an index **CSV**
  built by the maintainer's `collate-telemetry.sh` from the immutable `.summary.json` files. The
  `bundle_name` column links each row to its detailed `.tar.gz`.
- If rclone isn't set up or the folder isn't shared to the user, the script keeps the `.tar.gz`
  and prints its path so they can upload it manually.
