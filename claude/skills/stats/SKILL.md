---
name: stats
description: "Cost and usage observability for Claude Code sessions. Shows token usage, cost, and task metrics."
user_invocable: true
---

# Stats — Cost & Usage Observability

## Commands

- `/stats` — 7-day summary
- `/stats today` — Today only
- `/stats month` — Current month
- `/stats session` — Current session

## How to Execute

### Step 1: Log invocation

```bash
echo '{"ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","skill":"stats","project":"workspace","task":"stats invocation"}' >> ~/vault/logs/workflow.jsonl
```

### Step 2: Get cost/usage data

Run the appropriate ccusage command based on the user's argument:

| Command | ccusage invocation |
|---------|-------------------|
| `/stats` | `npx ccusage@latest --period 7d` |
| `/stats today` | `npx ccusage@latest --period 1d` |
| `/stats month` | `npx ccusage@latest --period 30d` |
| `/stats session` | `npx ccusage@latest --period 1d` (filter to current session in output) |

If ccusage fails or isn't available, fall back to reading JSONL files directly:
```bash
# Count sessions and estimate from local data
find ~/.claude/projects -name "*.jsonl" -mtime -7 | wc -l
```

### Step 3: Get task metrics from workflow log

Run the task metrics script with the number of days for the period:

```bash
python3 ~/.claude/skills/stats/scripts/task_metrics.py <days>
```

- `/stats today` → `python3 ~/.claude/skills/stats/scripts/task_metrics.py 1`
- `/stats` → `python3 ~/.claude/skills/stats/scripts/task_metrics.py 7`
- `/stats month` → `python3 ~/.claude/skills/stats/scripts/task_metrics.py 30`

### Step 4: Present combined summary

Format output as:

```
## Usage Summary (last 7 days)

### Cost & Tokens
[ccusage output — tokens in/out, cost, sessions]

### Tasks by Tier
  Quick: N
  Small: N
  Medium: N
  Large: N

### Workflow Activity
  Total skill invocations: N
  Verifications: N pass / N fail
```

For workflow activity, run the activity script with the number of days:

```bash
python3 ~/.claude/skills/stats/scripts/workflow_activity.py <days>
```
