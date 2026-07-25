---
name: task-triage
description: "Use when starting any new task, feature request, bugfix, enhancement, or refactoring to determine the appropriate level of process before doing any work."
---

# Task Triage

Before starting ANY new task, classify it into a tier and follow the corresponding process. Do not skip this step.

## Tier Assessment

Ask yourself these questions:
1. How many files will this touch?
2. Is the change obvious or does it need design thought?
3. Could this break existing behavior?
4. Does the user need to approve an approach?

## Worktree Guard (MANDATORY for Small+)

Before creating a branch for any Small, Medium, or Large task, you MUST use a git worktree. Never develop features in the main repo directory.

**Check:** Run `git worktree list` to see existing worktrees.

**Setup steps:**
1. `git worktree add ../<repo>-<feature> -b feat/<name> main`
2. **Copy** `.env` and credentials (e.g., `firebase-service-account.json`) into worktree — **COPY, not symlink** (Docker can't follow symlinks outside build context)
3. If Docker is needed: use `docker-compose.worktree.yml` with **UNIQUE names per worktree**:
   ```bash
   WT_NAME=todo-<abbrev> WT_API_PORT=<unique> WT_PG_PORT=<unique> COMPOSE_PROJECT_NAME=todo-<abbrev> \
     docker compose -f docker-compose.worktree.yml up --build -d
   # Port allocation: Main=8001/5433, WT1=8002/5434, WT2=8003/5435, WT3=8004/5436
   ```
4. All edits, tests, and commits happen in the worktree directory
5. Test with `docker exec todo-<abbrev>-backend` (matching your WT_NAME)

**CRITICAL:** Never reuse `COMPOSE_PROJECT_NAME` across worktrees — if two worktrees share a project name, one runs the other's code.

**After merge:** `COMPOSE_PROJECT_NAME=todo-<abbrev> docker compose -f docker-compose.worktree.yml down -v` then `git worktree remove ../<worktree>`

**Quick tasks are exempt** — they can be done directly on a branch in the main repo since they're trivial and short-lived.

## Tiers

### Quick (just do it)
**Signals:** Typo, config tweak, 1-line fix, version bump, obvious rename
**Process:** Fix it. Verify it works. Done.
**Worktree:** Not required (but don't work on main — create a branch).
**Do NOT:** Enter plan mode, write a design doc, create sub-tickets

### Small (worktree, implement, and test)
**Signals:** Bug fix touching 1-3 files, small enhancement, utility function, straightforward addition
**Process:** Create worktree → read relevant code → implement → write/update tests → verify → commit
**Worktree:** `git worktree add ../<repo>-<name> -b fix/<name> main` + isolated Docker stack
**Do NOT:** Enter plan mode for something you can hold in your head. Do NOT work in the main repo directory.

### Medium (worktree, plan, dispatch subagents)
**Signals:** New feature (single ticket), refactoring 3-8 files, new API endpoint, anything where the approach isn't obvious
**Process:** Create worktree → plan → create tasks with dependency graph → **dispatch independent tasks to subagents in parallel** → verify all outputs → commit → merge to main
**Worktree:** `git worktree add ../<repo>-<name> -b feat/<name> main` + isolated Docker stack
**Do:** Write a plan, get user sign-off, dispatch subagents for implementation, YOU verify and run tests
**Do NOT:** Execute tasks sequentially yourself when they can be parallelized via subagents

### Large (worktree, orchestrate with subagents)
**Signals:** Epic with 5+ sub-tickets, cross-cutting changes, new subsystem, multi-day effort
**Process:** Create worktree → plan mode → break into sub-tickets → **dispatch subagent batches (parallel where possible)** → two-stage review → verify → merge to main
**Worktree:** `git worktree add ../<repo>-<name> -b feat/<name> main` + isolated Docker stack
**Do:** Use fresh subagents per task, maximize parallel dispatch, run spec + quality reviews yourself

## Anti-Patterns

| Thought | Reality |
|---------|---------|
| "Let me just quickly..." on a Medium task | If it needs design thought, plan first |
| "This needs a full plan" for a Quick task | A typo fix doesn't need a design doc |
| "I'll figure it out as I go" on a Large task | You'll get lost at hour 2 without a plan |
| "I'll do these steps one by one" on Medium+ | If steps are independent, dispatch subagents in parallel |
| "Subagents are overkill for this" on Medium+ | Your job is to orchestrate, not to type code. Dispatch and verify |
| "I'll just write the backend then the frontend" | Backend and frontend are almost always parallelizable. Dispatch both |

## Examples

**"Fix the typo in the header"** → **Quick** — 1 file, obvious change, no design thought needed.

**"Add rate limiting to the /api/search endpoint"** → **Medium** — needs design decisions (algorithm, limits, storage), touches 3+ files (middleware, config, tests), could break existing behavior.

**"Rewrite the auth system to support OAuth2 + SAML"** → **Large** — cross-cutting (5+ files), multiple sub-tasks (provider config, token handling, session management, migration), multi-day effort.

## After Triage

State the tier briefly: "This is a **Small** task — I'll implement and test directly."
Then proceed with the appropriate process. Do not over-explain the triage.

## Task Tracking (MANDATORY for Small+)

After classifying the tier, you MUST create tracked tasks using `TaskCreate` before writing any code.

### Quick
No task tracking needed — just do it.

### Small
Create 1-3 tasks covering: implement → test → verify. Mark each `in_progress` before starting, `completed` after verifying.

### Medium
Create tasks for each step in the plan: migration, model changes, service changes, route changes, tests (RED), implementation (GREEN), integration verification. Set `addBlockedBy` for dependencies.

### Large
Create tasks for every ticket/sub-ticket in the plan. Each task must include:
- **Subject**: Clear imperative action (e.g., "Implement archive_task_with_children in TaskService")
- **Description**: Exact files, changes, and verification command
- **Dependencies**: `addBlockedBy` linking to prerequisite tasks

After creating all tasks, call `TaskList` to confirm the full plan is captured. Then execute in order — `in_progress` → work → verify → `completed` → next task.

**Never start coding without tasks created first.** If you catch yourself writing code without tracked tasks, STOP, create them, then continue.

## E2E Test Requirement (MANDATORY for Small+)

Any task that adds or modifies an API endpoint, user flow, or business logic MUST include E2E tests.

- **New endpoints**: Happy path + error paths (400, 404, 422)
- **Modified endpoints**: Regression test for changed behavior
- **New user flows**: Full journey start to finish
- **Brain dump actions**: Mock Gemini, verify proposal→submit→result
- **Where**: `backend/tests/e2e/` with E2EClient wrapper
- **Run**: `docker exec todo-backend python -m pytest tests/e2e/ -v --tb=long`
- **Skip when**: Pure refactoring (existing E2E covers), frontend-only, config/docs

## Logging (MANDATORY)

After classifying the tier, log it via Bash:

```bash
echo '{"ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","skill":"task-triage","project":"<project>","tier":"<Quick|Small|Medium|Large>","task":"<brief task description>"}' >> ~/vault/logs/workflow.jsonl
```
