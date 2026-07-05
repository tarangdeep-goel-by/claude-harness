# Secrets — example template

> Copy this file to a local `SECRETS.md` (gitignored) and fill in real values.
> `SECRETS.md` is never committed. This example file documents the expected shape only.

---

## Required

The harness core (session continuity, hooks, skills, `qmd` search) runs with **no secrets**.
Everything below is optional — add only what your own data/analysis stack requires.

## Optional — your data-stack credentials

Add whatever your analytics, database, or API stack requires. Examples:

| File / Env Var | Purpose | Notes |
|----------------|---------|-------|
| `~/.claude/.env.data-tools` | Shared data credentials (your analytics + database keys) | Sourced by `persist-env-hook.sh` at session start |
| `~/.claude/.gsheets-sa.json` | Google Sheets/Drive service-account key | From your GCP project → IAM → Service Accounts |
| `~/code/.env` | Project-level credentials | Conventional location; not committed |
| `YOUR_DB_API_KEY` | Your database or warehouse API key | Obtain from your data platform |
| `YOUR_ANALYTICS_TOKEN` | Your analytics platform session token | Obtain from your analytics platform |

After copying: `chmod 600 ~/.claude/.env* ~/.claude/*.json`.

Replace the placeholder names above with whatever your stack actually uses. There is no prescribed set — the harness core requires no secrets of its own.
