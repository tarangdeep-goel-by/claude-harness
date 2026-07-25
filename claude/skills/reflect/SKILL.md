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
- `/reflect memory` — Review durable memory candidates inferred by the Stop hook (see "Memory candidate flow" below)
- `/reflect memory apply <N>` — Promote candidate #N into canonical memory
- `/reflect memory dismiss <N>` — Mark candidate #N as dismissed

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
   - **Project-specific convention** → the project's own `CLAUDE.md` (whatever repo the learning came from — e.g. `~/Documents/Projects/<project>/CLAUDE.md` for a code repo's CLAUDE.md)
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

## Memory candidate flow (`/reflect memory`)

A separate queue from learnings: `~/vault/memory-review-queue.jsonl`. Candidates
are appended by `vault-scripts/memory-infer-hook.sh` (a Stop hook that calls
glm-4.7 at session end). Each line is a JSON object with:
- `kind`: `"memory_candidate"`
- `type`: `user` | `feedback` | `project`
- `name`: kebab-slug
- `description`: one-line summary
- `body`: concrete durable fact (1-3 sentences)
- `confidence`: `high` | `medium` | `low`
- `project`, `session_id`, `ts`, `source`
- `status`: `pending` | `applied` | `dismissed`

### `/reflect memory` — Show pending memory candidates

1. Read `~/vault/memory-review-queue.jsonl`.
2. Filter to `status == "pending"` AND `kind == "memory_candidate"`.
3. Sort by confidence **high → medium → low** (this order is canonical — the
   `apply`/`dismiss` commands index into this exact ordering).
4. Present a single numbered table (no per-confidence headers — the confidence
   column carries it):

```
## Pending memory candidates

| # | type | confidence | name | description | body |
|---|------|------------|------|-------------|------|
| 1 | feedback | high | prefer-motor-async | Prefers Motor over pymongo | "Use Motor (async) not pymongo in async repos." |
| 2 | user | medium | ... | ... | ... |
```

5. If empty: "No pending memory candidates. The memory-infer hook runs at
   session end and only appends durable, novel facts."

### `/reflect memory apply <N>` — Promote candidate into canonical memory

**SAFETY: NEVER auto-apply. Always show the table first and get explicit user
confirmation for the specific N.**

1. Show the pending table (above) if not already shown.
2. Confirm the candidate at index N with the user before writing anything.
3. Apply via the sibling script (handles file write + MEMORY.md line + status
   flip atomically):
   ```bash
   python3 ~/.claude/skills/reflect/scripts/apply_memory.py ~/vault/memory-review-queue.jsonl <N> apply
   ```
   - Writes `~/.claude/projects/<project-slug>/memory/<name>.md` (project-scoped, derived from your session cwd) with canonical frontmatter:
     ```
     ---
     name: <slug>
     description: <one-line>
     metadata:
       type: <type>
       confidence: <confidence>
       created: <today YYYY-MM-DD>
       last_verified: <today YYYY-MM-DD>
     ---
     <body>
     ```
   - Appends to `MEMORY.md` in that same dir: `- [<name>](<name>.md) — <description>`
   - Refuses to overwrite an existing `<name>.md` (reports the collision; user
     must dismiss or rename first).
   - Flips that queue entry's `status` to `applied`.
4. Run `qmd update && qmd embed` so the new memory is searchable.
5. Report the path written.

`apply_memory.py` reuses the same pending+sort logic as the display step, so the
N the user reads off the table always matches what the script applies. The
existing `update_learning.py` could not be reused because it keys on
`trigger_text` (a field that doesn't exist on memory candidates) — hence the
sibling script.

### `/reflect memory dismiss <N>` — Dismiss a candidate

1. Show the pending table if not already shown.
2. Confirm N with the user.
3. Flip status:
   ```bash
   python3 ~/.claude/skills/reflect/scripts/apply_memory.py ~/vault/memory-review-queue.jsonl <N> dismiss
   ```
4. Confirm: "Candidate #N dismissed."

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
