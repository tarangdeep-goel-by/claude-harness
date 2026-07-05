# /start-work — Day Start

The **day-level** complement of `/wrap-up`. Run once at the start of the day. It runs the
daily refresh jobs, surfaces what's carrying over, and shows any parallel sessions already
running. (For per-session catch-up on a specific goal, use `/recall` instead — that's the
session-level bookend.)

> Cadence model: **day** = `/start-work` ↔ `/wrap-up`; **session** (N per day, parallel) =
> `/recall` ↔ `/vault-push`.

## Steps

### 1. Day marker + daily jobs
- Check for today's day marker: `System/handoffs/YYYY-MM-DD/_day-started.json`.
- **If absent** (first session of the day):
  - Run the daily-jobs engine: `bash System/scripts/run-daily-jobs.sh`
  - Create the marker (the runner does this) recording `started_at` and the job results.
  - Report a status table: ✅ fresh (skipped) · ▶ ran · ⚠ failed, with log paths.
- **If present** (a later session today):
  - Don't re-run jobs. Report: "Day started HH:MM · N sessions so far." Offer
    `bash System/scripts/run-daily-jobs.sh --force` only if the user asks.

### 1b. Tuesday — Bonds weekly referral post
- **Only on Tuesdays** (`date +%u` = 2). The daily-jobs engine runs the `bonds-weekly-referral`
  job (dow-gated) which writes the Slack-formatted update to
  `~/.cache/referral_cost_v4/bonds_weekly_latest.txt` (F1 Referrer + F2 Referee + Investment/
  Spend/MTD, bond-campaign cohort — see [[0019-single-file-xlsx-patch-publish]] siblings / `bonds_weekly_update.py`).
- Read that file (confirm it's fresh — regenerated today; if the job failed/stale, say so and
  offer to re-run `bonds_weekly_update.py`).
- Present the update to the user, then **post it to `#daily-bonds-updates`** via the Slack MCP
  (`slack_send_message`, `mrkdwn`). Posting to a shared channel is outward-facing — show it and
  post on the user's confirmation (or immediately if they've said to auto-post).

### 2. Parallel sessions
- List live sessions from `~/vault/logs/active-sessions/*.json` → show each one's project,
  type (dev/analysis/pm), branch/worktree, and goal. ("You have 2 sessions live.")

### 3. Carry-over context
1. Read `System/dashboards/Open Items.md` — active items, highlight overdue / high priority.
2. Read the previous day's rollup: latest `System/handoffs/YYYY-MM-DD/_day.md`.
3. Read `Meta/agent-messages.md` — pending inter-agent messages.
4. Read today's `Daily/YYYY-MM-DD/` if it exists — scratchpad + unprocessed recordings.
5. Read `Meta/memory.md` for persistent context.

## Output format

```
## Day Start — [date]

### Daily Jobs
[table: job · status · last run · log]

### Bonds Weekly (Tuesdays only)
[the generated update + "posted to #daily-bonds-updates" / "awaiting confirm to post"]

### Live Sessions
[parallel sessions, or "none"]

### Carrying Over
[active Open Items — flag overdue/high priority]

### Yesterday
[summary from previous _day.md rollup]

### Pending
- [agent messages]
- [unprocessed recordings in today's Daily/]
- [untriaged scratchpad items]

### Suggested Focus
[based on open items + yesterday's rollup + new captures]
```
