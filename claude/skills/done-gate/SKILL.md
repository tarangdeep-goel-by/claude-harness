---
name: done-gate
description: "The completion gate. Use RIGHT BEFORE claiming work is done/fixed/passing/working — run the proof command, read the output, only claim with fresh evidence. Distinct from /verify (which drives the app to confirm runtime behavior); done-gate gates the 'done' CLAIM itself. Fires last in the dev workflow, after the work + /code-review."
---

# Done-Gate — Verify Before Claiming Done

## The Rule

**No completion claims without fresh verification evidence.**

Before saying "done", "fixed", "passing", "works", or "complete":

1. **IDENTIFY** — What command proves this claim?
2. **RUN** — Execute it now. Fresh. Not from memory or cache.
3. **READ** — Full output. Check exit code. Don't skim.
4. **CONFIRM** — Does the output actually prove what you're about to claim?
5. **REPORT** — Include the verification evidence in your response.

## What Counts as Verification

| Claim | Required Evidence |
|-------|-------------------|
| "Tests pass" | Run test suite, show output with pass count and exit code 0 |
| "Bug is fixed" | Run the reproduction case, show it no longer fails |
| "Feature works" | Run/demo the feature, show expected output. **If it touches an API endpoint, E2E tests must pass**: `pytest tests/e2e/ -v` |
| "Build succeeds" | Run the build command, show completion without errors |
| "No regressions" | Run full test suite, show all passing |

## Banned Language (Before Verification)

These phrases are NOT allowed until you have evidence:
- "should work", "probably fixed", "seems to pass", "likely resolved"
- "Done!", "All good!", "That should do it!"
- "I believe this fixes...", "This should resolve..."

**Instead say:** "Let me verify..." and then run the command.

## When You Can't Verify

Sometimes verification isn't possible (no test suite, requires manual UI check, external dependency). In that case, say so explicitly:

"I've made the change but can't verify automatically because [reason]. You'll need to [specific manual check]."

Never pretend you verified when you didn't.

## Logging (MANDATORY)

After verification (pass or fail), log it via Bash:

```bash
echo '{"ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","skill":"done-gate","project":"<project>","result":"<pass|fail>","task":"<brief task description>"}' >> ~/vault/logs/workflow.jsonl
```

## Task Tracking Check (MANDATORY)

Before reporting completion, verify the task list is up to date:

1. Call `TaskList` to see all tracked tasks.
2. Confirm the current task is marked `completed` (use `TaskUpdate` if not).
3. Confirm no tasks are stuck in `in_progress` that should be `completed` or need attention.
4. If all tasks for the plan/feature are done, state: "All tasks complete — [X/X] done."
5. If tasks remain, state what's next.

**Never claim a feature is "done" while tracked tasks are still pending or in_progress.**

## After Verification

Report concisely with evidence:
- "Tests pass (42 passed, 0 failed, exit code 0)"
- "Bug fixed — reproduction case now returns expected 200 instead of 500"
- "Build succeeds (docker build completed in 23s)"

## Self-Review Checklist (Run Before Claiming Done)

After verification passes, run this quick scan on changed files to catch leftover code smells:

```bash
# Get changed files and scan for common issues
git diff --name-only HEAD~1 2>/dev/null | xargs grep -nE \
  'TODO|FIXME|HACK|XXX|NotImplementedError|raise NotImplemented|console\.log\(|print\(.*debug|debugger;|\.only\(|_unused|PLACEHOLDER' \
  2>/dev/null || echo "Clean — no code smells found"
```

### What to check

| Pattern | Why it matters |
|---------|---------------|
| `TODO` / `FIXME` / `HACK` / `XXX` | Unfinished work left behind |
| `NotImplementedError` | Stub that was never filled in |
| `console.log()` / `print(...debug` | Debug logging left in |
| `debugger;` | JS debugger statement |
| `.only(` | Focused test that skips other tests |
| `PLACEHOLDER` | Placeholder text never replaced |

### Rules

- **Quick tasks:** Skip this checklist (overkill for typo fixes)
- **Small+ tasks:** Run the grep scan. Fix any hits or justify why they should stay.
- If hits are intentional (e.g., a TODO for a future ticket), note it in the completion message.
- Do NOT add this as a pre-commit hook — it's advisory, not blocking.

## Vault Push — After Successful Verification (Small+ Tasks)

After verification passes for **Small, Medium, or Large** tasks, push a completion note to the vault. Skip for Quick tasks.

### What to push

Append an entry to `~/vault/notes/<project>-completed.md` (create if it doesn't exist):

```markdown
### YYYY-MM-DD — <task title>
- **Tier:** Small/Medium/Large
- **What:** One-line summary of what was done
- **Decisions:** Key architectural or design choices made (if any)
- **Files:** Main files touched (3-5 max)
- **Learnings:** Anything worth remembering for next time (if any)
```

### How to push

1. Write/append the entry to `~/vault/notes/<project>-completed.md`
2. Run `qmd update && qmd embed` via Bash
3. Mention briefly: "Pushed completion note to vault."

### Rules

- Keep entries short — 3-5 lines max per task
- Use the project name from the working directory (e.g., `todo`, `ai-data-analyst-v2`, `ladder`)
- If project is unclear, use `general-completed.md`
- Don't push duplicate entries — check if the task was already logged
