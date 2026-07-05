> **TEMPLATE — adapt before use** (shareable scaffold from `claude-harness`).
> Keep the architecture, routing, cadence, and conventions below — they're the reusable core.
> Change only what's yours:
> - [ ] Your product area / scope — this was written around the author's area, not yours.
> - [ ] Run `/onboard` to fill `Meta/memory.md` (who you are, team, scope).
> - [ ] **Already used Claude Code here?** Don't start empty — run `./catalog-sessions.sh 30` in the
>       harness repo, then follow `ADOPT_FROM_HISTORY.md` to back-fill this vault from your last 30 days.
> - [ ] Add your own data-stack skills under `.claude/skills/` (company-specific data skills have
>       been stripped; bring your own analytics/Mixpanel/Metabase/PostHog skills as needed).

# PM Second Brain

## Session Start — MANDATORY

**Before answering ANY question, always read `Meta/memory.md` and search the vault (`Notes/`, `Daily/`, `System/dashboards/Open Items.md`) for relevant context. Use what you find to inform your response.** This is non-negotiable. Claude without vault context is a search engine with a personality. Claude with vault context is a chief of staff.

---

## Routing Rules — MANDATORY

This vault uses **skills** (interactive, run in main conversation) and **agents** (autonomous, run as subagents). Skills are preferred for anything needing user input.

### Skills (interactive — follow instructions directly, ask user questions)

| # | Skill | When to activate |
|---|-------|-----------------|
| 1 | **transcriber** | Meeting transcripts, recordings, "process this call", "meeting notes from" |
| 2 | **scribe** | "save this", "quick note", "jot this down", raw text dumps, capture requests |
| 3 | **sorter** | "triage", "sort my notes", "file my notes" |
| 4 | **compiler** | "compile", "synthesize docs", "digest docs", "build wiki", "process supporting docs" |

**How:** Read the skill's SKILL.md from `.claude/skills/<name>/` and follow the instructions directly. Stay in the main conversation. Ask the user questions as needed.

### Agents (autonomous — delegate via Agent tool)

| # | Agent | When to activate |
|---|-------|-----------------|
| 1 | **librarian** | "audit vault", "clean up", "broken links", "duplicates", "vault health" |

**How:** Delegate to the agent using the Agent tool. These run autonomously and return results.

### Slash Commands

Cadence model: **day** = `/start-work` ↔ `/wrap-up` (run once each per day); **session**
(N per day, often parallel) = `/recall` ↔ `/vault-push` (run at the start/end of each session).

| Command | What it does |
|---------|-------------|
| `/start-work` | **Day start** (complement of `/wrap-up`). Runs daily jobs, shows carry-over + live parallel sessions. |
| `/wrap-up` | **Day end** audit & triage (recordings, scratchpad, open items, memory; rolls up session handoffs, commits) |
| `/recall` | **Session start** — catch up on a goal; pull relevant context across past sessions (global skill) |
| `/vault-push` | **Session end** — persist this session: handoff, PROJECT_LOG, README/ARC, research links (global skill) |
| `/week-review` | Synthesize the week into a materialized weekly digest (global + per-project) |
| `/process-meeting` | Process transcript via transcriber skill (detailed, embeddable meeting notes) |
| `/new-note` | Create note with correct template |
| `/status` | Current initiatives, blockers, action items |
| `/new-project` | Scaffold a new project folder with README, PROJECT_LOG, and subfolders |
| `/compile` | Synthesize uncompiled supporting docs into research notes |
| `/maintain` | Vault health check via librarian agent |

---

## Architecture

This vault uses a project-centric architecture. Daily/ is the capture layer, Notes/ organizes knowledge by project, and Categories/Subjects provide cross-cutting navigation via Obsidian Bases views.

### Folder Structure

```
vault-work/
├── Daily/YYYY-MM-DD/              ← Day's capture: scratchpad, recordings, transcriptions, meeting notes
│   ├── YYYY-MM-DD.md                 Daily scratchpad (rough notes, todos, FYIs, reminders)
│   ├── recording_HHMMSS.m4a         Recordings
│   ├── recording_HHMMSS.txt         Transcriptions
│   └── meeting-topic.md             Processed meeting notes
│
├── Notes/<project-name>/          ← Project knowledge bases
│   ├── README.md                     Project overview, status, links
│   ├── PROJECT_LOG.md                Session history, decisions, rationale (updated every session)
│   ├── spec.md                       Product spec / PRD
│   ├── decisions/                    Key decisions with rationale
│   ├── research/                     Research, analysis, user studies
│   ├── supporting_docs/              External docs, user research, wireframes, analytics exports
│   ├── docs/                         Generated docs (DOCX exports, presentations)
│   └── meetings/                     Project-specific meetings + recordings
│
├── Categories/                    ← Bases views cutting ACROSS projects (by type)
├── Subjects/                      ← Bases views cutting ACROSS projects (by theme)
├── Meta/                          ← Memory file, agent messages
├── System/                        ← Templates, dashboards, scripts, handoffs
```

| Folder | Purpose |
|--------|---------|
| `Daily/YYYY-MM-DD/` | Day's capture layer. Everything from a day goes here first — scratchpad, recordings, transcriptions, meeting notes. |
| `Notes/<project>/` | Project knowledge bases. Each project is a folder with README, spec, decisions, research, docs, meetings. |
| `Categories/` | Bases views cutting across projects by **type** (what it is). Not storage — navigation only. |
| `Subjects/` | Bases views cutting across projects by **theme** (what it's about). Not storage — navigation only. |
| `People/` | Canonical note per person (org context). Link `[[Person Name]]` instead of repeating who-is-who. |
| `Glossary/` | Canonical note per **metric / product / tool** (`metrics/`, `products/`, `tools/`). Link `[[K-factor]]`, `[[Your Tool]]`. Carries `aliases:` for synonym recall; metrics point to `[[methodology]]` for exact logic. |
| `System/` | Templates, dashboards (including Open Items ledger), scripts, handoffs. Infrastructure only. |
| `Meta/` | Agent message board and vault metadata (memory.md). |

### How It Works

1. **Capture**: During the day, dump everything into `Daily/YYYY-MM-DD/` — rough notes in the scratchpad, recordings, transcriptions. Don't worry about structure.
2. **Process**: Meetings get transcribed and turned into structured notes in the daily folder. Optionally linked to a project's `meetings/` folder.
3. **Formalize**: Knowledge that has lasting value moves to `Notes/<project>/` — decisions, specs, research.
4. **Navigate**: Categories and Subjects use Obsidian Bases views (frontmatter tags) to surface notes across projects. They are navigation, not storage.
5. **Wrap-up**: End of day, `/wrap-up` triages the scratchpad collaboratively — todos go to Open Items, decisions get formalized, FYIs get enriched.

### Key Files

| File | Purpose |
|------|---------|
| `System/dashboards/Open Items.md` | Global persistent todo/action ledger. Items added, completed, or carried forward. Never resets. |
| `Meta/agent-messages.md` | Inter-agent message board |
| `Meta/memory.md` | Persistent memory — people, tools, processes, context |
| `System/handoffs/YYYY-MM-DD/` | Per-day folder: one `<session-id>.md` handoff per session + `_day.md` rollup (written by `/wrap-up`) |
| `Daily/YYYY-MM-DD/YYYY-MM-DD.md` | Daily scratchpad — todos, FYIs, quick notes, reminders |

### YAML Frontmatter Convention

```yaml
---
title: "Note title"
categories:
  - "[[Category Name]]"
subjects:
  - "[[Subject Name]]"
status: idea | draft | active | review | done | archived
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
```

### Knowledge-base conventions (keep recall gold)

These are MANDATORY when writing or updating notes — they're what makes recall reliable over time:

1. **Link to canonical entities.** When a note mentions a person, metric, product, or tool that
   has a `People/` or `Glossary/` note, link it (`[[K-factor]]`, `[[Your Tool]]`, `[[Person Name]]`).
   Don't redefine inline. If a recurring entity has no canonical note yet, create one from
   `System/templates/entity.md` (include `aliases:`).
2. **Every significant decision becomes an ADR.** When a real choice is made (architecture,
   approach, scope, tool), write a decision record in `Notes/<project>/decisions/NNNN-<slug>.md`
   from `System/templates/decision-record.md` (context / decision / rationale / consequences).
   Don't bury rationale in prose — isolate it so `recall decisions <topic>` finds it.
3. **Cite + date.** Research notes cite their source and carry `updated:`. Point to the canonical
   source (e.g. `[[methodology]]`) rather than restating formulas (avoids drift).
4. **Tag for navigation.** Fill `categories:` and `subjects:` so the cross-cutting Bases views work.
5. **Right doc type — the contract (don't conflate these).** Each project carries a
   **`KNOWLEDGE_BASE.md` = durable fundamentals only** (what it IS + HOW it works: mechanics, rules,
   constraints, key concepts, decisions-in-brief) — **NO metrics, NO status.** Findings/numbers →
   `research/`; metric→source→logic → `methodology`; rationale → `decisions/` ADRs; status & history →
   `PROJECT_LOG.md` / `PROJECT_ARC.md`; instrumentation/events → the skills. **The KB links OUT to those,
   it never restates them.** Template: `System/templates/knowledge-base.md`.

### Deliverable Standards — MANDATORY (sheets & research docs)

Every analytical deliverable lands as one of **two output types** — a **Google Sheet workbook**
or a **research markdown** (`Notes/<project>/research/`). Both follow the same spine: **lead with
the answer, then the method, then the evidence.** This applies to ALL projects, not just referral.

**1. Sheet workbooks — MANDATED tab order:**
`README → Summary (exec-first) → Methodology → Trend → deep-dives` (raw data, reconciliation,
samples, side-streams). The first four are required; deep-dives are project-specific.
- **README** — front door: what it is, window, sources, "why counts moved", tab guide.
- **Summary** — an **Exec Summary block first** (the answer, computed from live data), then the cuts.
- **Methodology** — filter/definitions, universe boundary, exclusions, how it differs from any rival
  cut, caveats. This is the credibility backstop.
- **Trend** — the time series, with coverage caveats on the tab.
- **Deep-dives** — the supporting detail, opened only when challenged.

**2. Every tab is self-explanatory.** Intro + caveat line(s) at the top; **lead with the answer**;
description columns for any taxonomy; label keyword/proximity counts **"indicative"**; state the
**basis** and flag when a tab is on a broader/different basis than the headline ("do NOT reconcile
line-by-line"). Numbers that should reconcile must reconcile (verify sums).

**3. Durable, not orphaned.** Each workbook has **(a) ONE generating pipeline script** (no orphaned
scratch scripts — promote them) and **(b) ONE collating doc** `Notes/<project>/scripts/<NAME>_WORKBOOK.md`
(sheet id, rebuild command, pipeline table, tab inventory, methodology decisions, open items).
**Mirror every live-sheet edit back into the script** so a rebuild reproduces it — never leave
live-only changes. No leftover/contradictory fragments (clear them). Template:
`System/templates/sheet-workbook.md`.

**3a. Persist all pulls — pulls must be deterministic.** Every DB/API/LLM pull **writes its raw
result to a local cache** (`~/.cache/<workbook>/…`), and downstream compute reads the **persisted
cache**, never the live source again — so a re-run reproduces the same numbers (the source drifts;
the cache doesn't). **Cached data is NEVER committed** (it's regenerable, not a git artifact —
`.gitignore` it); the **pull/regenerate SCRIPT is the durable artifact** and MUST be re-runnable
(`--pull`/`--refresh`). If the cache is absent, the pipeline **re-pulls or skips gracefully with a
pointer to the regenerate script** — it never hard-fails on missing data and never depends on
committed data. (Exemplar: `build_outbound_audit.py` → `~/.cache/cx_workbook/`.)

**4. Research markdown** uses `System/templates/research-doc.md`: cite + date, link canonical
entities, isolate decisions as ADRs — same "answer → method → evidence" order.

### Categories (note types)

PRDs, Meeting Notes, One-on-Ones, Decisions, Customer Feedback, Research, Retrospectives, Sprint Notes, OKRs, Feature Requests, Competitive Analysis, Launch Plans

### Subjects (themes)

Product Strategy, User Experience, Growth & Metrics, Engineering, Design, Stakeholders, Processes, Compliance

---

## Skills & Agents

4 interactive skills (run in main conversation) + 1 autonomous agent (run as subagent).
All check `Meta/agent-messages.md` for pending messages before starting.

### Skills (interactive)

| Skill | Role |
|-------|------|
| **scribe** | Raw text → clean structured notes. Asks which project. |
| **transcriber** | Meeting recordings → structured notes. 6 meeting types. Asks clarifying questions. |
| **sorter** | Triages Daily/ scratchpad. Asks you to classify each item. |
| **compiler** | Synthesizes supporting_docs/ into research notes. Cites sources, surfaces contradictions, cross-links. |

### Agents (autonomous)

| Agent | Role |
|-------|------|
| **librarian** | Vault health audits, broken links, missing frontmatter |

## Inter-Agent Messaging

Agents communicate via `Meta/agent-messages.md`. Format:

```
### [timestamp]
⏳ → TO: [Agent] | FROM: [Agent]
[Message content]
```

Resolved: change `⏳` to `✅`, add `**Resolution**: [what was done]`

## Session Continuity

Two nested loops. The **day loop** bookends the whole day; the **session loop** runs N times
inside a day, often in parallel. See `System/docs/HOW_THIS_SYSTEM_WORKS.md` for the
full design.

**Core invariant (parallel-session safe):** session commands write only session-scoped files
(`System/handoffs/<date>/<sid>.md`); day commands are the sole writers of shared aggregates
(`_day.md` rollup, structured `Open Items.md`). Code work runs in per-task git worktrees.

- **Day start** — `/start-work`: runs daily jobs (`System/daily-jobs.yaml`), reads Open Items +
  yesterday's `_day.md` rollup + agent messages, shows live parallel sessions.
- **Session start** — `/recall`: pull cross-session context for this session's goal (temporal,
  topic, project-scoped, or lens modes).
- **During** — work in worktrees (dev) or on your project libraries (analysis); agents read/write
  vault files and the message board.
- **Session end** — `/vault-push`: write the session handoff, update PROJECT_LOG / README /
  PROJECT_ARC, link research docs, append todos to the Open Items inbox.
- **Day end** — `/wrap-up`: roll up session handoffs into `_day.md`, reconcile the Open Items
  inbox, triage scratchpad, update memory, commit.

### Temporal hierarchy (queryable via `/recall`)

| Granularity | Doc | Query |
|---|---|---|
| Session | `System/handoffs/<date>/<sid>.md` + a `PROJECT_LOG` entry | `recall last session [project]` |
| Day | `System/handoffs/<date>/_day.md` | `recall <date>` |
| Week | computed live (default); optional `System/handoffs/weekly/<YYYY-Www>.md` + `Notes/<proj>/digests/` via `/week-review` | `recall last week [project]` |
| Project lifetime | `Notes/<proj>/PROJECT_ARC.md` + `PROJECT_LOG.md` | `recall context <project>` |
