---
name: reflect
description: "Review and apply detected learnings from past sessions. Shows corrections, decisions, and discoveries detected by the learning loop."
user_invocable: true
---

# Reflect — Self-Improving Learning Loop

## Commands

- `/reflect` — Show pending learnings grouped by confidence (HIGH first)
- `/reflect apply` — Approve and apply a learning to the appropriate config file
- `/reflect dismiss` — Mark a learning as dismissed
- `/reflect stats` — Show counts by status

## Queue File

Learnings are stored in `~/vault/learnings-queue.jsonl`. Each line is a JSON object with:
- `confidence`: HIGH / MEDIUM / LOW
- `category`: correction / decision / discovery
- `trigger_text`: The user message that triggered detection
- `proposed_learning`: Concise actionable rule
- `project`: Which project it came from
- `status`: pending / applied / dismissed

## How to Execute

### `/reflect` — Show pending learnings

1. Read `~/vault/learnings-queue.jsonl`
2. Filter to entries where `status == "pending"`
3. Group by confidence level (HIGH first, then MEDIUM, then LOW)
4. Present as a numbered table:

```
## Pending Learnings

### HIGH (corrections)
| # | Project | Learning | Trigger |
|---|---------|----------|---------|
| 1 | ai-data-analyst-v2 | Use motor instead of pymongo | "No, don't use pymongo directly..." |

### MEDIUM (decisions)
| # | Project | Learning | Trigger |
|---|---------|----------|---------|
| 2 | ladder | Use Fiber v3 for new endpoints | "Let's go with Fiber v3..." |

### LOW (discoveries)
[...]
```

5. If no pending learnings, say: "No pending learnings. The learning detector runs automatically at session end."

### `/reflect apply` — Apply a learning

**SAFETY: NEVER auto-apply. Always present for user review.**

1. Show pending learnings (as above) if not already shown
2. Ask user which learning to apply (by number)
3. Ask user to confirm the target file:
   - **Project-specific convention** → the project's own `CLAUDE.md` (whatever repo the learning came from — e.g. `~/Documents/vault-work/CLAUDE.md` for the PM vault; there is no standard `~/Documents/Projects/` layout)
   - **Global workflow convention** → `~/.claude/CLAUDE.md`
   - **Skill-specific** → `~/.claude/skills/<skill>/SKILL.md`
4. **Check for conflicts**: Read the target file and check if the proposed learning contradicts an existing rule. If so, flag the conflict and ask user how to resolve.
5. **Create backup** before modifying:
   ```bash
   cp <target_file> <target_file>.bak.$(date +%Y%m%d%H%M%S)
   ```
6. Append the learning as a concise rule (1-2 lines) to an appropriate section of the target file
7. Update the entry's status to "applied" in the queue file:
   ```bash
   python3 ~/.claude/skills/reflect/scripts/update_learning.py "<TRIGGER_TEXT>" applied "<TARGET_FILE>"
   ```
8. Run `qmd update` to re-index

### `/reflect dismiss` — Dismiss a learning

1. Show pending learnings if not already shown
2. Ask user which learning to dismiss (by number)
3. Update entry status to "dismissed" in queue file:
   ```bash
   python3 ~/.claude/skills/reflect/scripts/update_learning.py "<TRIGGER_TEXT>" dismissed
   ```
4. Confirm: "Learning #N dismissed."

### `/reflect stats` — Show counts

```bash
python3 ~/.claude/skills/reflect/scripts/learning_stats.py
```

## Logging (MANDATORY)

```bash
echo '{"ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","skill":"reflect","project":"workspace","task":"reflect invocation"}' >> ~/vault/logs/workflow.jsonl
```

## Rules

- **NEVER auto-apply** learnings. Always present for user review and approval.
- **Create backups** before modifying any file.
- **Flag conflicts** if a learning contradicts an existing rule.
- **Keep applied learnings concise** — 1-2 lines max.
- **Dedup** — don't apply the same learning twice to the same file.
