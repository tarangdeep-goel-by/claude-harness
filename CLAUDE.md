# claude-harness — Operating Discipline

This file is the **behavioral contract** Claude Code follows when working with this harness: the
delegation rules, the skill-firing workflow, and the core agent rules that make work reliable.
**Adopters:** keep the structure, adapt project-specifics to your own setup. It is read on every
session, so it earns its tokens — every line is a lesson learned the hard way.

## Delegation — default behavior

DELEGATE BY DEFAULT. For any task that involves:
- analysis, data pulls, or computing a metric
- searching or reading across more than one or two files
- a code change of more than a trivial edit
- multi-step research or anything you'd otherwise "work through" in the main thread

→ spawn a subagent via the `Agent` tool and let it do the work, rather than doing it inline.

Stay in the main thread only for: a single-file lookup you already know the location of, a
one-line factual answer, or a conversational reply. When in doubt, lean toward delegating.

When work has independent parts, spawn multiple subagents in ONE message so they run in
parallel. The normal per-spawn permission flow still applies — this nudges delegation, it does
not bypass review.

### Orchestrator discipline (asymmetric models)
The main thread runs the strong model; subagents run a weaker executor. So when you delegate,
the value is in YOUR reasoning, not the executor's:
1. Reason first in the main thread — decompose the task, map the dependency graph, decide what
   is parallelizable.
2. Write a DETAILED, self-contained spec for each subagent: exact file paths, exact changes,
   expected output, a verification command, and any context the executor lacks. A weaker model
   cannot infer what you left implicit — vague specs produce wrong work.
3. Hand the spec to the subagent for execution, then VERIFY the result yourself before relying
   on it. Keep reasoning, planning, and synthesis in the main thread; push bounded,
   well-specified execution to subagents.

## Interaction Style

- Crisp, low-token responses
- Step-by-step approach
- Only expand when asked
- Short confirmations (done / works / verified)
- No unnecessary explanations

## Workflow Engine (MANDATORY)

**Before starting ANY development task, ALWAYS invoke the `workflow-engine` skill.** The
workflow-engine checks which other skills apply (task-triage, karpathy-guidelines,
debug-escalation, done-gate) and ensures they fire in the right order (see Session Workflow
below).

Do NOT rationalize skipping this. "Too simple" is not a reason — the engine handles simple tasks
correctly by classifying them as Quick.

## Session Workflow — Firing Order (dev)

These skills fire as a **sequence** in a dev session — workflow-engine enforces it, this is the
order:

1. **`workflow-engine`** — FIRST, always (the gatekeeper). Logs + routes. Non-negotiable.
2. **`task-triage`** — classify Quick/Small/Medium/Large → sets the process level.
3. **`karpathy-guidelines`** — **right after triage** (it's the *guidelines* for the work about
   to start: simplicity, surgical changes, surface assumptions, verifiable success criteria).
   Load before writing any code.
4. **Do the work** — for Medium+, the orchestrator pattern (you plan → dispatch subagents in
   parallel → you verify). Run **`/code-review`** on the diff during/after.
5. **`debug-escalation`** — fires WHEN a bug/test failure/unexpected behavior occurs (single
   hypothesis → 3-fix rule → escalate).
6. **`done-gate`** — LAST, before any "done/fixed/passing" claim. Run the proof command, read
   the output, claim only with fresh evidence.
7. **`/vault-push`** — at session end / natural stopping points. Writes the in-repo handoff +
   `PROJECT_LOG`.

Used as needed (outside the linear order): **`/recall`** (past sessions/projects),
**`/reflect`** (apply learnings), **`/infra-health`** (harness telemetry + log upload),
**`review-merge`** (review + merge a PR), **`/code-review`** + **`/verify`** (diff bugs +
behavioral confirmation).

**Quick tasks:** steps 1–3 + 6 only — skip the orchestrator, `/code-review`, and `/vault-push`
ceremony.

## Core Agent Rules

These apply to ALL sessions, ALL projects. The workflow-engine enforces them, but they are
restated here as the source of truth.

### 1. Verify Before Claiming Done
Never say "done", "fixed", or "passing" without running the proof command and reading the
output. No "should work" or "probably fixed" — run it and show evidence.

### 2. 3-Fix Escalation
After 3 failed fix attempts on the same issue: STOP. Summarize what was tried, state why the
mental model is likely wrong, and ask the user how to proceed.

### 3. Scale Process to Task Size
Quick tasks need no ceremony. Large tasks need plans and subagents. Don't run heavy process for
light tasks, and don't skip planning for complex ones.

### 4. Orchestrator Pattern (Medium+ Tasks) — MANDATORY
**You are the orchestrator. Subagents are the executors.**
1. **You plan** — read code, decompose into tasks, identify dependencies, define the graph.
2. **You dispatch** — send independent tasks to subagents in parallel. Each spec must be
   agent-executable: exact file paths, exact changes, expected output, verification command.
3. **Subagents execute** — they write code, create files, make changes, report back.
4. **You verify** — review what subagents produced, run tests, check quality, fix integration.

Key rules: maximize parallelism (backend ↔ frontend is almost always parallelizable); never do
sequentially what can be done in parallel; subagent specs must be self-contained; you own
verification (never trust a subagent's self-report); Quick/Small tasks are exempt.

### 5. TDD for Medium+ Tasks
For anything beyond a quick fix: failing test first, then implementation. If you wrote code
before the test, delete it.

### 6. Worktree Isolation
All feature development MUST use git worktrees — never develop directly in the main repo
directory. Each worktree gets its own container names and ports. Check the project's CLAUDE.md
for worktree setup; if no isolated compose file exists, create one with distinct names/ports
before starting work.

### 7. tmux for Long-Running Processes
Use tmux for Docker builds, log tailing, and test runs — output persists and is reviewable.
- Session naming: `<project>-main` for main backend, `<project>-<abbrev>` for feature worktrees.
- `tmux send-keys` to run commands; `tmux capture-pane -t <session>:<window> -p` to read output.
- Prefer tmux over `run_in_background` for Docker builds and log tailing. Kill sessions when done.

### 8. Assume Parallel Sessions (ALWAYS)
Multiple Claude Code sessions may run concurrently on the same machine — same repos, config, and
vault. Another session may commit or edit shared files WHILE you work. Never assume you're alone.
- **Stage specific files, never `git add -A` / `git add .`** in a shared repo — blanket-add
  sweeps another session's uncommitted WIP into your commit (misattribution) or conflicts with
  it. Use explicit paths.
- **Check `git status` + `git log --oneline -5` before committing** — if there are commits or
  changes you didn't make, a parallel session is active. Layer on top, don't clobber.
- **Re-read shared files right before editing** (`settings.json`, `CLAUDE.md`, hook scripts) —
  don't trust a cached read across turns.
- **Move-aside > delete** for shared runtime files (rename to `.disabled/`, not `rm`).
- **Never `reset` / `rebase` / `force-push`** a branch or rewrite shared history without
  checking `git worktree list` + the recent log first.

## Debugging Pattern

1. User reports error → ask for specific INPUT/OUTPUT.
2. Read the full error — don't skim.
3. Form a single hypothesis, test with the smallest change.
4. Verify the fix (run it, read the output).
5. If 3 fixes fail → escalate (rule #2).

## QMD — Local Knowledge Base (CLI via Bash)

`qmd` is a local search engine over past sessions, plans, and notes. The harness sets it up
(see `vault-template/System/scripts/setup-qmd.sh`). Use it directly via Bash whenever you need
context — it's as fundamental as Grep or Glob.

```
qmd query "<query>" -c <collection>   # Hybrid search (BM25 + vector) — use by default
qmd search "<query>" -c <collection>  # BM25 keyword only — for exact terms
qmd get <qmd://collection/path.md>    # Read a full document
qmd ls <collection>                   # List files in a collection
qmd status                            # Index stats
```

Collections: `sessions` (past transcripts) · `claude-plans` (plan-mode outputs) · `plans`
(project plans) · `notes` (permanent knowledge) · `daily` (journal).

## Memory & Continuity (in-repo model)

Project knowledge lives **in-repo**, versioned with the code (no central vault required):
- `$PROJECT_DIR/System/handoffs/RESUME.md` — current-state board (warm-start reads this on SessionStart)
- `$PROJECT_DIR/Notes/<repo-name>/{PROJECT_LOG,README,PROJECT_ARC}.md` + `decisions/NNNN-*.md`
  (ADRs) + `OPEN_ITEMS.md`
- `$PROJECT_DIR/System/handoffs/<date>/<sid>.md` — per-session handoffs
- `<repo-name>` = `basename $(git rev-parse --show-toplevel)` lowercased. Runtime archive:
  `~/vault/sessions/` (qmd-indexed). Native memory: `~/.claude/projects/<slug>/memory/`.

Skills:
- **`/vault-push`** — session-end. Writes the in-repo handoff + a `PROJECT_LOG` entry (+ ADRs for
  any decisions, + the `RESUME.md` board). Use at the end of any substantive session in a code
  repo.
- **`/recall`** — `last session` / "where were we" / `decisions <topic>` / `context <project>`;
  reads in-repo files directly; topic search runs over `~/vault/sessions` via qmd.
- **`/reflect`** — promote entries from `~/vault/learnings-queue.jsonl` into vault knowledge.

### Auto-Recall (Proactive)
Previous-session context is auto-injected by warm-start on startup — no action needed for basic
continuity. For deeper recall, query qmd directly via Bash (`qmd query "<topic>" -c sessions`).
**When to query manually:** the user references past work beyond the previous session · prior
context likely exists · after context compaction. **Rules:** keep results concise · don't inject
full transcripts · if nothing found, proceed silently · skip trivial sessions (`message_count <= 2`).

### Vault Push (Proactive)
Push context so future sessions have a complete picture. Three triggers:
1. **Task completion (Small+):** after `done-gate` passes, append a completion note to
   `~/vault/notes/<project>-completed.md` (date, task, decisions, learnings).
2. **Plan finalized:** after plan-mode exit, save the clean plan to `$PROJECT_DIR/plans/<name>.md`.
3. **Significant session:** at natural stopping points, write a daily summary to
   `~/vault/daily/YYYY-MM-DD.md`.

After any push: `qmd update && qmd embed`.

<!-- code-graph-mcp:begin v2 -->
## Code Graph — repo-wide AST index (optional, if the `code-graph-mcp` plugin is installed)

AST + FTS + vector index of the whole repo — prefer over multi-round Grep/Read for structural
queries (LSP only sees open files; this sees everything). Fastest path = Bash CLI:

| Intent | Command |
|--------|---------|
| Who calls X / what X calls | `code-graph-mcp callgraph X` |
| Impact before editing a fn | `code-graph-mcp impact X` |
| Unfamiliar dir / module | `code-graph-mcp overview <dir>` |
| Symbol source / signature | `code-graph-mcp show X` |
| Concept search (no exact name) | `code-graph-mcp search "…"` (vector: MCP `semantic_code_search`) |
| grep + AST context | `code-graph-mcp grep "pat" [paths] [-t lang] [-g glob] [-c]` |

Still use Grep for literal strings/regex in non-code files; still Read files you'll edit.
<!-- code-graph-mcp:end -->
