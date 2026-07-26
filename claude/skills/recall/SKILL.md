---
name: recall
description: "Search past Claude Code sessions, notes, and daily entries from the local vault. Use when the user says 'recall X', 'where were we', 'what did we do about X', 'remember working on X', 'look up past work on X', or wants to resume/catch up on prior sessions. Supports temporal, topic, graph, and analysis lens modes (retro, decisions, gaps, patterns, context)."
---

# /recall — Context Memory Search

Search past Claude Code sessions, notes, and daily entries from the local vault.

## Usage

```
/recall <mode> <query>
```

**Mode routing — pick by what the user actually wants:**

| The ask | Mode |
|---|---|
| "Where were we" / catch up on the cwd repo | **0** — `/recall` (in-repo files, no qmd) |
| "What happened yesterday / last week / on <date>" | **temporal** (1 / 1b) |
| "What do we know about <topic>" | **topic** (qmd over `~/vault/sessions`) |
| "What links to / relates to <note, person, metric>" | **graph** |
| "What worked / what didn't" | lens: **retro** (qmd) |
| "Why did we choose X" | lens: **decisions** (in-repo ADRs first, then qmd) |
| "What's unfinished / dropped" | lens: **gaps** (qmd) |
| "What keeps recurring" | lens: **patterns** (qmd) |
| "Restore everything to resume paused work" | lens: **context** (in-repo ARC/LOG first, then qmd) |

## Modes

### 0. Where were we — the session-start "catch me up" (the most common use)

This is how a **work session starts**: catch me up on where a thread was left. Two flavors:

- **On a project (the common case — parallel work tabs):** `/recall <project>` → assemble the
  resume point from three sources, newest-first:
  1. The **newest per-session handoff for the project** — glob `System/handoffs/**/*.md` and pick
     the most recent whose `project:` frontmatter matches (this is the deepest current-state
     snapshot). Handle **both** handoff shapes (see below).
  2. The **latest `$PROJECT_DIR/Notes/<repo-name>/PROJECT_LOG.md` entry** (history/depth — the newest
     `## YYYY-MM-DD · …` heading — uniform H2, per the merged vault-push convention).
  3. The project's **section of `System/handoffs/RESUME.md`** *if the board exists* (the L0
     current-state pointer — read it first when present; it's the fastest "where's the thread now").
  Lead from the board section / newest handoff (where the thread is now), then the latest
  PROJECT_LOG entry + open threads + recent project context
  (`qmd query "<project> <topic>" -c projects -c handoffs -c sessions`). This is the load-bearing
  per-project resume.
- **Global / operational tab:** `/recall` (no project) → if `RESUME.md` exists, read its
  `last_touched` section first (last thing touched anywhere) + a reference line per other active
  thread (latest PROJECT_LOG entry); otherwise fall back to the newest handoff across
  `System/handoffs/**/*.md` (or that day's `_day.md` rollup) + the latest PROJECT_LOG entry per
  recently-touched project.

**Both handoff shapes — the reader must handle either:**
- **Legacy flat:** `System/handoffs/<date>.md` (one file per day, older vault layout).
- **Current per-session:** `System/handoffs/<date>/<sid>.md` (one handoff per session) plus the
  day rollup `System/handoffs/<date>/_day.md` (written by `/wrap-up`).

Always glob `System/handoffs/**/*.md` so both shapes are picked up; filter by `project:`
frontmatter, and sort by date (folder or filename) to find "newest". If a `_day.md` rollup exists
for a day, prefer it for a day-level ask; for the deepest current state prefer the newest
`<sid>.md`.

The warm-start hook may already auto-surface the board's / newest handoff's last-touched state at
tab start; this mode is the deeper, **project-scoped** catch-up — and the way to swap from the
last-touched thread to the project you're actually on.

**Mode 0 output template (budget ≤ 15 lines — a resume point, not a history lesson):**
```
## Where we left off: <project>
**Now:** <2-3 lines — in-flight state + immediate next step, from RESUME section / newest handoff>
**Last session:** <sid8> · <date> · <one-line outcome>
**Open threads:** <up to 3 bullets>
**Resume with:** <the concrete command / file / step the handoff names>
(sources: <handoff path> · <PROJECT_LOG path>)
```

### 1. Temporal — Search by time

```
/recall yesterday
/recall last week
/recall 2026-03-01
```

**How to handle:**
1. Parse the time expression into a date range
2. List files in `~/vault/sessions/` that match the date range (filenames start with `YYYY-MM-DD`)
3. Use `ls ~/vault/sessions/` and filter by date prefix
4. Read matching files and provide a summary of each session (title, project, key topics)
5. If many sessions match, list them with one-line summaries; offer to deep-dive into specific ones

### 1b. Project-scoped temporal & the temporal hierarchy

`/recall` is the read side of the temporal hierarchy maintained by `/vault-push` + `/wrap-up`.
Map the request to the right granularity:

| Ask | What to read |
|-----|--------------|
| `recall last session [project]` | Newest `$PROJECT_DIR/System/handoffs/<date>/<sid>.md` (filter by `project:` frontmatter if a project is named). |
| `recall <date>` / `recall yesterday` | That day's `System/handoffs/<date>/_day.md` rollup (fall back to the per-session files if no rollup yet). |
| `recall last week` (all projects) | Compute on demand: read all `_day.md` (or session handoffs) in the date range + `qmd query` sessions. (No materialized weekly digest — that tier was retired.) |
| `recall last week <project>` | **Slice** `$PROJECT_DIR/Notes/<repo-name>/PROJECT_LOG.md` by the `## YYYY-MM-DD · …` headings in range + the project's session handoffs in range. (`grep -E '^##+ [0-9]{4}-'` tolerates legacy `###` entries when slicing.) |
| `recall context <project>` / "span of the project" | `$PROJECT_DIR/Notes/<repo-name>/PROJECT_ARC.md` (the throughline) + the full `PROJECT_LOG.md`. |
| `recall <entity>` (a person/metric/product/tool) | Read the canonical note in `People/` or `Glossary/` FIRST (the definition), then `qmd query` for everything linking it. |
| `recall decisions <topic>` | `$PROJECT_DIR/Notes/<repo-name>/decisions/*.md` (in-repo ADRs) + the `decisions` lens. |

**Entity-first + aliases:** for a person/metric/product/tool, the canonical `People/`/`Glossary/`
note is the answer's spine — read it first, then fan out to mentions. Entity notes carry an
`aliases:` list, so a query for "viral coefficient" should match `[[K-factor]]`; if `qmd` misses
it, also `grep -rl "aliases:.*<term>" People Glossary`.

**Project filtering:** session handoffs carry `project:` in frontmatter — grep that, not the
filename. `PROJECT_LOG.md` entries are headed `## YYYY-MM-DD · <sid> · <type> · <summary>` (H2;
tolerate legacy `###` when slicing with `grep -E '^##+ [0-9]{4}-'`) —
a date-range slice of those headings answers any project+window question even with no digest.

Weekly is always computed on demand — the materialized weekly-digest tier (`/week-review`, `handoffs/weekly/`, `digests/`) was retired 2026-07-01.

### 2. Topic — Search by content

```
/recall topic authentication
/recall topic docker deployment
/recall topic graphs
```

**How to handle:**
1. Use `qmd` CLI via Bash to search:
   - `qmd query "<query>" -c sessions` — hybrid search (BM25 + vector), best for most queries
   - `qmd search "<query>" -c sessions` — BM25 keyword search, for exact term matching
   - `qmd get <file>` — read a full session file for deeper context
2. If `qmd` is not available (fallback):
   - Use `grep -rl "query" ~/vault/` to find matching files
   - Read the top matches and synthesize
3. Present results as a synthesized summary with links to source sessions
4. Include relevant excerpts from the most relevant sessions

### 3. Graph — Visualize session connections

```
/recall graph
/recall graph last 7 days
```

**How to handle:**
1. Read YAML frontmatter from all session files in `~/vault/sessions/`
2. Extract: date, project, title, session_id
3. Generate a self-contained HTML file with a D3.js force-directed graph:
   - Nodes = sessions (colored by project)
   - Edges = sessions that share the same project or date
   - Node size = message_count
   - Hover shows title + date
4. Save to `/tmp/recall-graph.html`
5. Open with `open /tmp/recall-graph.html`

## Filtering Rules

These rules apply to ALL modes (temporal, topic, graph, lenses):

1. **Trivial session filter:** Always skip sessions where `message_count <= 2` in the YAML frontmatter. These are incomplete or abandoned sessions with no useful context.
2. When multiple exports of the same session exist (same `session_id`), prefer the one with the highest `message_count`.

### 4. Analysis Lenses

Lenses provide structured analysis across multiple collections. Each lens has a specific purpose, query strategy, and output template.

```
/recall retro <topic>
/recall decisions <topic>
/recall gaps <topic>
/recall patterns <topic>
/recall context <topic>
```

#### retro — Retrospective

**Purpose:** What worked, what didn't, what to do differently next time.

**Query strategy:**
1. `qmd query "<topic>" -c sessions` — find relevant sessions
2. `qmd query "<topic> error OR bug OR fix" -c sessions` — find problems
3. `qmd query "<topic>" -c work-daily` — check daily reflections

**Output template:**
```
## Retro: <topic>

### What Worked
- ...

### What Didn't
- ...

### Do Differently
- ...

Sources: [session files]
```

#### decisions — Decision Log

**Purpose:** Extract architectural and design decisions with rationale.

**Query strategy:**
1. `qmd query "<topic> decision OR chose OR architecture" -c sessions`
2. `qmd query "<topic>" -c plans`
3. `qmd query "<topic>" -c claude-plans`

**Output template:**
```
## Decisions: <topic>

| Date | Decision | Rationale | Source |
|------|----------|-----------|--------|
| ... | ... | ... | ... |
```

#### gaps — Unfinished Work

**Purpose:** Find dropped threads, unfinished work, and outstanding TODOs.

**Query strategy:**
1. `qmd query "<topic> TODO OR unfinished OR defer OR hack" -c sessions`
2. `qmd query "<topic> TODO OR incomplete" -c plans`

**Output template:**
```
## Gaps: <topic>

### Open Items
- [ ] ...

### Deferred Decisions
- ...

Sources: [session files]
```

#### patterns — Recurring Patterns

**Purpose:** Identify recurring patterns, anti-patterns, and common fixes.

**Query strategy:**
1. `qmd query "<topic>" -c sessions` — broad context
2. `qmd query "<topic> pattern OR always OR recurring" -c sessions` — explicit patterns
3. `qmd query "<topic>" -c notes` — check permanent notes

**Output template:**
```
## Patterns: <topic>

### Recurring
- ...

### Anti-patterns
- ...

### Common Fixes
- ...

Sources: [session files]
```

#### context — Full Context Restore

**Purpose:** Restore full context for resuming paused work. Most comprehensive lens.

**Query strategy:**
1. `qmd query "<topic>" -c sessions` — recent sessions
2. `qmd query "<topic>" -c plans` — active plans
3. `qmd query "<topic>" -c claude-plans` — plan mode outputs
4. `qmd query "<topic>" -c notes` — permanent notes
5. `qmd query "<topic>" -c work-daily` — daily journal

Focus on the most recent results. Present chronologically.

**Output template:**
```
## Context: <topic>

### Current State
- ...

### Recent Activity
- ...

### Active Plans
- ...

### Key Decisions
- ...

Sources: [session files]
```

#### General lens rules

- Apply the trivial session filter (`message_count <= 2`) to all results
- Read top 3-5 results per collection queried
- Use `qmd search` for exact terms, `qmd query` for semantic matching
- Cite sources with session file paths
- Be honest when data is sparse — say "limited data" rather than fabricating

## Response Format

Always start with a brief summary line, then details:

```
Found 5 sessions matching "authentication" (2 this week, 3 older)

### [Session Title] — 2026-03-04
- Project: ai-data-analyst-v2
- Key points: ...
- [Full session →](file path)
```

## Notes

- Vault location: in-repo project knowledge at `$PROJECT_DIR/System/handoffs/` + `$PROJECT_DIR/Notes/<repo-name>/` (where `$PROJECT_DIR` = `git rev-parse --show-toplevel` and `<repo-name>` = its basename lowercased); runtime session archive at `~/vault/sessions/` (qmd-indexed).
- Sessions are markdown files with YAML frontmatter
- QMD collections vary by machine/vintage — **run `qmd collection list` FIRST and use only names
  that exist.** Do NOT guess variants: an unknown `-c` errors out and **silently drops that source**
  from the search (the project CLAUDE.md documents this trap — e.g. on the main work vault there is
  NO `daily` collection; the daily journal is `work-daily`). Known name pairs across machines:
  `daily`↔`work-daily` (daily journal), `notes`↔`vault-notes` (permanent notes),
  `plans`↔`claude-plans` (plan-mode outputs); plus `sessions`, `projects` (`$PROJECT_DIR/Notes/<repo-name>/` —
  PROJECT_LOG/ARC/research), `handoffs` (`System/handoffs/**`), `glossary`, `people`, `meta`. Use
  `-c projects` for PROJECT_LOG/ARC/research, `-c handoffs` for handoffs, `-c glossary -c people`
  for entities.
- Session filenames follow: `YYYY-MM-DD_project_slug_sessionid.md`
- Always use `qmd` CLI via Bash — do NOT use QMD MCP tools
