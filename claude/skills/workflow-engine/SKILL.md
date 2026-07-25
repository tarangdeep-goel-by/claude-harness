---
name: workflow-engine
description: "Use at the start of every conversation and before every task, implementation, debugging session, or completion claim. This skill governs which other skills must be invoked. You MUST check this skill before doing any work."
---

# Workflow Engine

This is the gatekeeper skill. It determines which skills apply to your current task. You MUST run this check before doing any work.

## Logging (MANDATORY)

Every time this skill is invoked, log it via Bash:

```bash
echo '{"ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","skill":"workflow-engine","project":"<project>","task":"<brief task description>"}' >> ~/vault/logs/workflow.jsonl
```

Replace `<project>` and `<brief task description>` with actual values. This is non-negotiable — if there's no log line, the skill wasn't invoked.

## Worktree & Branch Guard (Run Before Any Code Change)

Before writing, editing, or deleting any code file, check where you are:

```bash
git worktree list
git rev-parse --abbrev-ref HEAD
pwd
```

**Worktree Rules (Small+ tasks):**
- For Small, Medium, and Large tasks: you MUST work in a git worktree, not the main repo directory.
- Check `git worktree list` — if no worktree exists for this feature, create one before writing code.
- Setup: `git worktree add ../<repo>-<feature> -b feat/<name> main`
- **Copy** `.env` and credentials into worktree — **COPY, not symlink** (Docker can't follow symlinks outside build context)
- Each worktree MUST use a **unique** `COMPOSE_PROJECT_NAME`, `WT_NAME`, and ports:
  ```bash
  WT_NAME=todo-<abbrev> WT_API_PORT=<unique> WT_PG_PORT=<unique> COMPOSE_PROJECT_NAME=todo-<abbrev> \
    docker compose -f docker-compose.worktree.yml up --build -d
  # Ports: Main=8001/5433, WT1=8002/5434, WT2=8003/5435, WT3=8004/5436
  ```
- Test with `docker exec todo-<abbrev>-backend` (matching your WT_NAME)
- **NEVER** reuse `COMPOSE_PROJECT_NAME` across worktrees — causes one to run the other's code
- Quick tasks are exempt — they can work directly in the main repo on a branch.

**Branch Rules:**
- If on `main` (or `master`), you MUST create a branch before any code change — no exceptions.
- Branch naming: `feat/<short-description>`, `fix/<short-description>`, or `chore/<short-description>`
- Never commit directly to main.
- If you realize you've been editing in the main repo for a non-Quick task, STOP. Create a worktree and move your work there.

## Plan Decomposition & Task Tracking (MANDATORY)

When the user references a plan file (e.g., `plans/*.md`) or asks to execute/implement a plan:

### 1. Read and decompose
- Read the full plan file.
- Break it into atomic, executable steps. Each step should be one clear action (e.g., "Create migration 008", "Write 10 archive tests", "Update TaskService with archive methods").
- If the plan already has tickets/sub-tasks, use those. If not, create them.
- Respect the plan's dependency order — identify what blocks what.

### 2. Create TaskCreate entries for EVERY step
- Use `TaskCreate` for each step BEFORE starting any work.
- Set `addBlockedBy` for dependencies (e.g., frontend ticket blocked by backend ticket).
- Tasks must have clear, specific subjects in imperative form.
- Description must include: files to modify, what to change, how to verify.

### 3. Dispatch to subagents (Medium+ tasks)

**You are the orchestrator. Subagents execute. You verify.**

- **Analyze the dependency graph** — identify which tasks are independent and can run in parallel
- **Dispatch independent tasks simultaneously** via the Agent tool — don't execute them yourself sequentially
- Each subagent spec must be **self-contained**: include file paths, existing code patterns to follow, API contracts, and the verification command
- **You verify after each batch completes** — run tests, check integration, review output
- Use `TaskUpdate` to mark tasks `in_progress` when dispatching, `completed` after YOUR verification passes
- If a subagent's work fails verification, fix it yourself or re-dispatch with corrected spec

**Common parallel groups:**
- Backend migrations + model changes (independent of each other)
- Backend service + router (can be parallel if API contract is defined)
- Backend work + frontend work (always parallelizable once API contract exists)
- Backend tests + frontend tests (always independent)

**Quick/Small tasks are exempt** — do these yourself directly.

### 4. Track progress visibly
- After completing each batch, call `TaskList` to show overall progress.
- The user should always be able to see: what's done, what's in progress, what's remaining.

**This is non-negotiable.** Plans without tracked tasks lead to lost context, skipped steps, and incomplete work. Every plan becomes a task list. Every task gets tracked to completion.

## Skill Check (Run Before Every Task)

For each item below, check if it applies. If it does, you MUST invoke that skill.

### Starting new work? → THEN immediately load guidelines
**Invoke:** `task-triage` → followed immediately by **`karpathy-guidelines`**
**Trigger:** User asks you to build, fix, add, change, refactor, or implement anything.
**What it does:** task-triage classifies Quick/Small/Medium/Large and sets the process level. **karpathy-guidelines fires right after** — it's the *guidelines* for the work about to start (simplicity, surgical changes, surface assumptions, verifiable success criteria), so load it before writing any code. The two are a pair; always run them in this order.

### Writing or modifying code? (already loaded if you just triaged)
**Invoke:** `karpathy-guidelines`
**Trigger:** You are about to write, edit, or refactor code. If you just ran task-triage above, this is already loaded — don't double-invoke.
**What it does:** Enforces simplicity, surgical changes, and goal-driven execution.

### Encountering a bug or error?
**Invoke:** `debug-escalation`
**Trigger:** A test fails, a command errors, behavior is unexpected, or the user reports a bug.
**What it does:** Enforces structured debugging with the 3-fix escalation rule.

### About to claim work is done?
**Invoke:** `done-gate`
**Trigger:** You are about to say "done", "fixed", "passing", "works", or "complete".
**What it does:** Requires fresh command output proving the claim before you can make it. Also pushes a completion note to the vault for Small+ tasks. (Distinct from `/verify`, which drives the app to confirm runtime behavior — done-gate gates the claim.)

### Finalizing a plan?
**Action:** Push clean plan to project `plans/` directory
**Trigger:** You exit plan mode after the user approves a plan.
**What to do:**
1. Save a clean copy of the plan to `~/Documents/Projects/<project>/plans/<descriptive-name>.md`
2. Run `qmd update` via Bash to index it
3. Mention briefly: "Pushed plan to vault."

## Enforcement Rules

1. **Check skills BEFORE your first action** — not after you've already started
2. **If in doubt, invoke the skill** — false positives are cheap, missed enforcement is expensive
3. **Never rationalize skipping** — "this is too simple" is not a valid reason to skip task-triage
4. **Quick tasks still get triaged** — task-triage will correctly classify them as Quick and let you proceed fast
5. **Multiple skills can apply** — a debugging session might invoke both debug-escalation AND done-gate

## Examples

**User says:** "Fix the typo in the README"
→ Invoke `task-triage` → Quick tier → just fix it, no plan needed

**User says:** "Add a new /health endpoint to the API"
→ Invoke `task-triage` → immediately invoke `karpathy-guidelines` (writing code) → Small/Medium
→ When done, invoke `done-gate` before saying "done"

**User says:** "The tests are failing after my last commit"
→ Invoke `task-triage` → then `debug-escalation` (bug encountered)
→ If 3 fixes fail → escalation kicks in automatically

## When Skills Don't Apply

You do NOT need to invoke skills for:
- Answering questions about code (reading, explaining, searching)
- Pure research or exploration (no implementation)
- Conversation that isn't a development task
- Follow-up questions within an already-triaged task

## Anti-Skip Patterns

| Thought | Response |
|---------|----------|
| "This is too simple for skills" | Task-triage handles this — it will classify as Quick |
| "I already know what to do" | Good — triage will confirm and you'll start in 5 seconds |
| "Skills will slow me down" | Skipping verification slows you down more when you claim false success |
| "I'll check skills after I start" | No. Check BEFORE. That's the whole point. |
