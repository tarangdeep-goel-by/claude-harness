# HOW THIS SYSTEM WORKS — Claude Code Continuity + Discipline Harness

**Audience: you, Claude, at the start of a session.** This explains the paradigm so you can (a)
understand the vault structure, (b) operate the continuity loop correctly, and (c) build knowledge
that survives months — not just sessions.

The guiding idea: *"Claude without vault context is a search engine with a personality; Claude with
vault context is a chief of staff."* Every session starts by reading the vault. The vault is the
durable memory; Claude is the operator over it.

---

## 1. The mental model

This is a **PM second brain**: a knowledge-base vault paired with a Claude Code harness. The PM owns
a product area (referral growth, payments, onboarding — whatever is yours). All analytical work,
decisions, meeting notes, and research accumulates here and becomes retrievable via `/recall`.

## 2. Two things both called "vault" (don't conflate them)

- **`~/Documents/vault-work/`** — the **knowledge base**: an Obsidian vault + its own git repo.
  Curated, durable PM knowledge. Notes, projects, decisions, daily captures live here.
- **`~/vault/`** — the **harness runtime** (created by `install.sh`): hook scripts (symlinks),
  telemetry logs, raw session exports (`~/vault/sessions/`), the learnings queue.
  Machine-local, mostly regenerable.
- Flow: **raw machine output → `~/vault` → distilled by you → `~/Documents/vault-work`.**

## 3. Vault architecture (project-centric)

Capture flows **down** into dailies, **formalizes** into projects, and is **navigated across** by
tag-views. Folder taxonomy:

- `Daily/YYYY-MM-DD/` — capture layer: scratchpad, recordings, transcriptions, raw meeting notes.
- `Notes/<project>/` — project knowledge bases. Each has `README.md`, `PROJECT_LOG.md` (session
  history/decisions), `PROJECT_ARC.md` (lifetime throughline), `spec.md`, `decisions/` (ADRs),
  `research/`, `supporting_docs/`, `docs/`, `meetings/`, `KNOWLEDGE_BASE.md`.
- `Categories/` — cross-project views by **type** (PRDs, Meeting Notes, Decisions, Research…).
- `Subjects/` — cross-project views by **theme** (Product Strategy, Growth & Metrics, Compliance…).
  Both are **navigation only** (Obsidian Bases over frontmatter), not storage.
- `People/` — one canonical note per person. `Glossary/` — one canonical note per
  **metric / product / tool** (`metrics/`, `products/`, `tools/`), each with `aliases:` for recall.
- `System/` — infrastructure: `templates/`, `dashboards/` (incl. the global **Open Items** ledger),
  `scripts/`, `handoffs/`, `docs/`, `daily-jobs.yaml`.
- `Meta/` — `memory.md` (mandatory session-start read) + `agent-messages.md` (inter-agent board).
- Root `CLAUDE.md` — the operating manual (routing rules, architecture, conventions). **Read it; it
  is the authoritative spec for this paradigm.**

## 4. Skills & agents (the capability layer)

**Skills = interactive (run in the main conversation, ask the user questions). Agents = autonomous
(delegated, run headless).**

- *Capture/curate skills (the starter loop — ships with the kit):* **scribe** (raw text → clean
  note), **transcriber** (recordings → structured meeting notes, 6 meeting types), **sorter**
  (triage Daily/ into the vault), **compiler** (supporting_docs → research notes). A mature vault
  often **archives all but transcriber** once its **domain skills** take over the day-to-day (capture
  goes straight into analysis scripts + project docs) — keep or archive per how you actually work.
- *Continuity skills:* **recall** (search past sessions/notes — temporal/topic/graph/lens modes),
  **vault-push** (session-end persistence), **start-work / wrap-up / week-review / status** (cadence),
  **dev-task** (code change end-to-end in an isolated git worktree → PR → CI → merge), **infra-health**
  & **stats** (harness telemetry vs cost), **maintain** (delegates to the librarian).
- *Domain skills:* add your own under `.claude/skills/` for product-specific workflows (data
  queries, analytical runbooks, CX investigation scripts, etc.).
- *Maintenance:* a **librarian** pass (broken links, dupes, frontmatter, drift) — ships as an agent,
  but mature vaults run it as an **ad-hoc general-purpose subagent** (the pattern is *no standing
  agents*: skills-first, delegate search/maintenance to disposable subagents).
- Inter-agent coordination via `Meta/agent-messages.md` (⏳ pending / ✅ resolved).

> Practical human companion to this paradigm: **`USING_THE_HARNESS.md`** — the daily rhythm, how
> skills auto-route, and when each fires.

## 5. The two cadence loops

Two nested loops (described in this document — see sections 1–4 above):

- **Day loop:** `/start-work` (run jobs, show carry-over + live parallel sessions)
  ↔ `/wrap-up` (triage scratchpad, reconcile Open Items, roll session handoffs into a `_day.md`,
  update memory, commit). Once each per day.
- **Session loop:** `/recall` (pull context for this session's goal) ↔ `/vault-push` (write a
  per-session handoff + update PROJECT_LOG/README/ARC + link research). N times per day, often
  parallel.
- **Parallel-safe invariant:** session commands write only **session-scoped** files
  (`System/handoffs/<date>/<session-id>.md`); day commands are the sole writers of shared
  aggregates (`_day.md`, the structured Open Items ledger). Code work happens in **per-task git
  worktrees** so parallel sessions never collide.

## 6. The harness wiring

`~/code/claude-harness` is the source repo; `install.sh` **symlinks** `settings.json` + global
skills into `~/.claude` and the hook scripts into `~/vault/scripts` (single source of truth — edit
the live file = edit the repo). Lifecycle hooks (all bash in `~/vault/scripts`):

- **SessionStart:** session-marker (heartbeat), warm-start (inject git state + project docs + qmd
  context), persist-env.
- **PreToolUse:** file-guard (block .env/keys/credentials), block-dangerous (rm -rf, force-push…).
- **PermissionRequest:** auto-allow Read/Glob/Grep, allow-python.
- **PostToolUse:** tool-telemetry (Skill/Task → events.jsonl), auto-test.
- **SubagentStart:** inject coding conventions into subagents.
- **PreCompact:** export full transcript before summarization.
- **Stop:** completion-check (catch stubs), auto-checkpoint (git stash), session-export
  (JSONL→markdown into `~/vault/sessions`), session-marker (liveness heartbeat), tool-telemetry.
- **Search spine:** **qmd** (semantic search) indexes both vault trees + `~/.claude/plans`;
  `/recall` runs on it. Models auto-download (~2.2GB).
- **Daily jobs:** `daily-jobs.yaml` — configure your own scheduled data refreshes here.

## 7. The conventions that make recall reliable (MANDATORY)

These are *why* the knowledge stays usable over months. Adopt them on day one:

1. **Link canonical entities** — mention a person/metric/product/tool → wikilink it
   (`[[K-factor]]`, `[[Your Tool]]`, `[[Person Name]]`); define once in People/Glossary, never inline.
2. **Every real decision → an ADR** in `Notes/<project>/decisions/NNNN-slug.md`
   (context/decision/rationale/consequences). Rationale is isolated, not buried in prose.
3. **Cite + date** research; point to `methodology` rather than restating formulas (avoids drift).
4. **Tag frontmatter** (`categories:`, `subjects:`, `status:`, `created/updated:`) so the Bases
   views work.
5. **Right doc type (the contract):** `KNOWLEDGE_BASE.md` = durable fundamentals only (what it IS +
   how it works) — *no metrics, no status*. Numbers → `research/`; metric→source→logic →
   `methodology`; rationale → `decisions/`; status/history → `PROJECT_LOG`/`PROJECT_ARC`. The KB
   links out, never restates.
6. **Deliverable standards:** every analytical output is either a **spreadsheet workbook** or a
   **research markdown**, both leading **answer → method → evidence**. Workbooks follow
   `README → Summary → Methodology → Trend → deep-dives`. Each workbook has **one** generating
   pipeline script + **one** collating `<NAME>_WORKBOOK.md`. **Cache discipline:** every DB/API/LLM
   pull writes a local cache; downstream reads the cache (deterministic re-runs); caches are
   gitignored; the **script** is the durable artifact.

## 8. Adding your domain

This template ships with generic continuity/capture skills. You bring your domain:

- **Data skills:** write a skill for your analytics stack (Mixpanel, PostHog, Metabase, BigQuery,
  Redshift…) that encodes your event names, table schemas, and query patterns. Store it under
  `.claude/skills/<name>/SKILL.md` in your vault.
- **Investigation runbooks:** encode forensic workflows (e.g. "investigate why user X didn't get
  reward") as skills so the methodology is repeatable and not re-invented each session.
- **Daily jobs:** configure `System/daily-jobs.yaml` with your scheduled data refreshes.

The endpoint: a single system that accumulates your product knowledge, makes past decisions
retrievable, and keeps every Claude session grounded in what you already know.
