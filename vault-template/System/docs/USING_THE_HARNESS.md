# Using the Harness — how to work with the skills

**Audience: a human operating this vault.** How the day flows, how the skills are meant to be
triggered, and how to get the most out of them. The paradigm/"why" is in `HOW_THIS_SYSTEM_WORKS.md`;
the authoritative routing/architecture spec is the root `CLAUDE.md`. This is the practical
"how do I actually use it" companion.

Guiding idea: *Claude without vault context is a search engine with a personality; Claude with vault
context is a chief of staff.* The vault is the durable memory; every session starts by reading it.

---

## 1. The daily rhythm (two nested loops)

| Loop | Open with | Close with | How often |
|---|---|---|---|
| **Day** | `/start-work` — runs daily jobs, shows carry-over + live parallel sessions | `/wrap-up` — triage scratchpad, reconcile Open Items, roll handoffs into `_day.md`, update memory, commit | once/day |
| **Session** | `/recall <topic>` (or just start — warm-start injects context) | `/vault-push` — write a per-session handoff + update PROJECT_LOG / README / ARC | N times/day, often parallel |

**Parallel-safe by design:** session commands write only session-scoped files
(`System/handoffs/<date>/<session-id>.md`); day commands own the shared aggregates. Code work happens
in **per-task git worktrees** so parallel sessions never collide. Run several chats at once — just
`/vault-push` each before it's lost.

## 2. How the skills are meant to be used

The core discipline is **load the matching skill *before* answering — even for a quick ask.**

- **Skills auto-route.** A `UserPromptSubmit` hook (`skill-router-hook.sh`) reads your prompt, detects
  intent, and nudges the right skill(s). You usually don't have to name them.
- **You can also invoke explicitly** with `/<skill-name>` (e.g. `/recall`, `/vault-push`).
- **Interactive skills ask you questions.** They run *in the conversation* (not headless) and will
  stop to clarify scope, confirm before committing, pick a type, etc. Answer them.
- **Never guess data.** The whole point of a data skill is that it encodes your real event names /
  table names — legacy variants silently return wrong data. Data question → load the data skill →
  use its documented names, never a guess.
- **Skills-first, subagents for scale.** Analysis and code are delegated to subagents (they write;
  the main thread reviews). The recommended pattern is **no standing agents** — search / cross-linking
  / maintenance run as ad-hoc general-purpose subagents. The main thread plans, briefs, and verifies.

## 3. The skill map

**Continuity & housekeeping (ships with the kit):**

`/start-work` · `/vault-push` · `/wrap-up` · `/recall` · `/status` · `/new-note` · `/new-project` ·
`/process-meeting` · `/compile` · `/maintain` (vault health) · `/reflect` (apply detected learnings) ·
`/infra-health` (hook/skill/job telemetry) · `/stats` (cost/tokens) · `/dev-task` (code change →
worktree → PR → CI → merge).

**Capture (the starter loop — optional):** `transcriber` (recordings → notes) is the one most vaults
keep; `scribe` / `sorter` / `compiler` are archivable once domain skills take over (see
`HOW_THIS_SYSTEM_WORKS.md` §4).

**Domain skills — you bring these (the daily drivers).** Write a skill under `.claude/skills/<name>/`
for each part of your stack, so the knowledge is encoded once and auto-routes:

| Example domain skill | Encodes |
|---|---|
| an **analytics** skill (Mixpanel / PostHog / Amplitude…) | your event names, funnel definitions, property gotchas |
| a **warehouse / SQL** skill (BigQuery / Redshift / Metabase…) | which table has what, join keys, column semantics |
| a **chart/report builder** | how to build + commit a saved report to your dashboards |
| an **investigation runbook** | a repeatable forensic workflow ("why didn't X happen for user Y?") |
| a **codebase** skill | your repo's build/test/PR conventions for a `dev-task` |

The endpoint: a data question routes to your analytics skill; a "which table" question routes to your
warehouse skill; end of a work block → `/vault-push` so the next `/recall` resumes exactly where you
left off.

## 4. The rules that keep it reliable

- **Search the vault first** — `qmd query "<topic>"` (semantic) / `qmd search` (exact) before
  answering from scratch; your memory is injected at session start.
- **Encode logic once** — put query/business logic in a skill or a shared lib, not copy-pasted across
  scripts that then diverge.
- **Worktrees for code repos** — never edit a primary checkout of a shared repo; make a per-task
  worktree.
- **Conventions that keep recall gold** — link canonical entities (`[[metric]]`, `[[person]]`), write
  ADRs for real decisions, cite + date research, right-doc-type (KB = fundamentals, numbers →
  research, status → PROJECT_LOG).

## 5. Go deeper

- **`CLAUDE.md`** (vault root) — the authoritative operating manual (adapt the domain bits).
- **`HOW_THIS_SYSTEM_WORKS.md`** — the paradigm/"why", including the continuity loop (§5) and the
  conventions that keep recall reliable (§7).
- **`/infra-health`** — is the harness itself healthy (hooks firing, skills routing, jobs fresh)?
