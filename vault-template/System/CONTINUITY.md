---
title: "Session Continuity — the fused stack (L0–L3 ladder × day/session cadence)"
type: system
created: 2026-06-16
updated: 2026-07-01
supersedes:
  - System/CONTINUITY.md
  - System/docs/SESSION_CONTINUITY_ARCHITECTURE.md
---

# Session Continuity

> **This governs _episodic_ memory** (what happened, when — append-only, one writer). Its peer,
> `System/KNOWLEDGE.md`, governs _semantic_ memory (what is true / what we decided — how the
> knowledge store mutates: owners, freshness, supersession). Two memory systems, two laws.

How we carry state across sessions and days. This is the **single** source of truth — it
replaces both the old `CONTINUITY.md` (the L0–L3 ladder) and the temp machine's
`SESSION_CONTINUITY_ARCHITECTURE.md` (the 2×2 day/session cadence). They describe the *same*
system from two angles:

- The **ladder (L0–L3)** answers *"at what altitude do I read/write state?"* — a compression
  stack where each layer is a lossy summary of the one below. Enter at the altitude your
  question needs.
- The **2×2 cadence** answers *"which command runs when, and who is allowed to write?"* — the
  day loop bookends everything (`/start-work` ↔ `/wrap-up`, once each); the session loop runs
  N times inside a day, often in parallel (`/recall` ↔ `/vault-push`).

**The law (both framings share it):** every tier is a matched **`WRITE ↔ READ`** pair with
**exactly one writer**. An unpaired tier is a failure — **write-only** = dead cost (logged,
never retrieved), **read-only** = a *stale trap* (retrieved, never maintained). No rung without
both halves; no artifact with two writers.

---

## 1. The cadence — two nested loops (the 2×2)

```
                  ── START ──────────────────  ── END ───────────────────────
  DAY     (1×)    /start-work                  /wrap-up
                  daily-jobs engine + domain    audit · triage · roll up sessions
                  syncs · descend L0→L3         → _day.md · reconcile Open Items · commit

  SESSION (N×,    /recall                      /vault-push
  parallel)       catch up: pull cross-session  persist: RESUME (L0) · <sid>.md (L1) ·
                  context for this goal         PROJECT_LOG/ARC/OPEN_ITEMS (L2) · decisions · inbox
```

| Command | Scope | Lives in | Complement |
|---------|-------|----------|-----------|
| `/start-work` | Day (1×, morning) | vault-work project command | `/wrap-up` |
| `/wrap-up` | Day (1×, evening) | vault-work project command | `/start-work` |
| `/recall` | Session (N×, start) | global skill | `/vault-push` |
| `/vault-push` | Session (N×, end) | global skill | `/recall` |

**Why the split:** session commands are **global** (a session can be dev in `~/code/*`, analysis,
or PM work anywhere), so `/recall` + `/vault-push` work in any repo. Day commands are
**vault-scoped** because the day-brain (Open Items, daily jobs, the day rollup) lives in the vault.

**A day** = 1 operational tab (`/start-work` → ops/meetings → `/wrap-up`) **+** N project tabs
(`/recall <project>` → work → `/vault-push` each), often concurrent.

---

## 2. The hard constraint — parallel sessions are the default

Assume 2–4 sessions running concurrently. The design rule that removes the clobber races:

> **Session commands write only session-scoped files. Day commands are the sole writers of
> shared aggregate files.**

### 2.1 Session identity
- On `SessionStart`, write a marker: `~/vault/logs/active-sessions/<session-id>.json`
  `{ session_id, cwd, project, branch, worktree, started_at, last_active, pushed, goal }`.
- **Liveness is a heartbeat:** the `Stop` hook fires after every assistant turn (no reliable
  "session closed" event), so it bumps `last_active`. Live = heartbeat within 45 min; markers
  stale > 12h are pruned.
- `/vault-push` sets `pushed:true`, clearing the unpushed warning.
- `/start-work` and `/status` read this dir → "You have 3 sessions live: 2 dev, 1 analysis."

### 2.2 The one-writer-per-artifact map (roles — no overlap)

| Artifact | Altitude | Keyed by | **Sole writer** | Role (what it answers) |
|----------|----------|----------|-----------------|------------------------|
| `System/handoffs/RESUME.md` (per-project board) | **L0** | project section | `/vault-push` (touched section only) | **WHERE** — the pointer, current-state only |
| `System/handoffs/<date>/<sid>.md` | **L1** | session_id | `/vault-push` | **WHAT** — this session's detail |
| `System/handoffs/<date>/_day.md` | **L1** | day | `/wrap-up` **only** | day rollup (merges the `<sid>.md`s) |
| `Notes/<proj>/PROJECT_LOG.md` `## YYYY-MM-DD` | **L2** | project | `/vault-push` | **ARC** — how it got here (history) |
| `Notes/<proj>/PROJECT_ARC.md` | **L2** | project | `/vault-push` (pivots only) | the throughline / north star |
| `Notes/<proj>/OPEN_ITEMS.md` | **L2** | project | `/vault-push` (add/tick/carry) | **forward** — this project's todos |
| `Notes/<proj>/research/*.md` | cut | topic | `/vault-push` / `/analysis` | analysis output (one doc per run) |
| `Notes/<proj>/decisions/*.md` | cut | decision | `/vault-push` (session-end peel) | **WHY** — ADRs |
| `System/dashboards/Open Items.md` (tables) | **L3** | day | `/wrap-up` (sole structured writer) · `/vault-push` may tick-done resolved items | forward state — cross-cutting / ops only (project todos are L2) |
| `System/dashboards/Open Items.md` `## Inbox` | **L3** | append | sessions append; `/wrap-up` reconciles | race-free intake |
| `~/vault/sessions/<sid>.md` (transcript) | src | session_id | export hook | raw source |
| `workflow.jsonl` / `hooks.jsonl` | tel | — | hooks | telemetry |
| code repos (`~/code/*`) | — | session-task | worktree per task | **no collisions — worktrees** |

> **Roles, stated once so they never overlap:** `RESUME.md` = pointer (**where**) ·
> `<sid>.md` = session detail (**what**) · `_day.md` = day rollup · `PROJECT_LOG.md` `## YYYY-MM-DD`
> = arc (**how it got here**) · `OPEN_ITEMS.md` = project forward-todos · `decisions/` = **why**. The board links to the log, never restates it.

---

## 3. The ladder (L0–L3) — read/write altitudes

| L | Tier — artifact | ✍️ WRITE (when · writer) | 👁️ READ (when · reader) |
|---|---|---|---|
| **L0** | **NOW** — `System/handoffs/RESUME.md` (per-project board; one `## <project>` section, current-state only) | every session-end · `/vault-push` (overwrite **only the touched section**; set `last_touched`) | every session-start · warm-start (auto-surfaces `last_touched` section in full + a 1-line ref per other active thread from its latest `PROJECT_LOG` entry) + `/recall`; `/start-work` re-reads once daily |
| **L1** | **DAY** — `System/handoffs/<date>/<sid>.md` (per session) + `System/handoffs/<date>/_day.md` (rollup) | per-session `/vault-push` (`<sid>.md`) · EOD `/wrap-up` (`_day.md`, merges them) | `/start-work` (prev-day `_day.md`, else legacy flat `<date>.md`) · `/recall` (globs `handoffs/**/*.md`) |
| **L2** | **PROJECT** — `Notes/<proj>/PROJECT_LOG.md` (history) + `PROJECT_ARC.md` (throughline) + `OPEN_ITEMS.md` (forward todos) | every session per touched project · `/vault-push` (log every session; ARC on a pivot/phase boundary; OPEN_ITEMS add/tick/carry) | project resume · `/recall context <project>` |
| **L3** | **STATE (forward, global)** — `System/dashboards/Open Items.md` — cross-cutting / ops todos only (project todos are L2) (+ per-project `EXPERIMENTS.md`) | sessions **append** to `## Inbox (unsorted)`; `/wrap-up` reconciles the structured tables (sole writer); `/vault-push` may tick-done resolved items | `/start-work` (Open Items + `updated:` staleness flag) |
| **cut** | **DECISIONS ("why")** — `Notes/<proj>/decisions/` | session-end peel · `/vault-push` | `/recall decisions <topic>` |
| **src** | transcripts → `~/vault/sessions/*.md` + `Daily/<date>/` | auto · export / `/vault-push` | `/recall` |
| **tel** | `workflow.jsonl` (skill/push activity) · `hooks.jsonl` (hook health) | hooks | `/vault-audit`, `/stats` · debug |

> **No PORTFOLIO tier** — dropped deliberately (paperwork, low value). Cross-project state lives
> in Open Items + per-project README/PROJECT_ARC.

### Diagram

```
   EVERY SESSION START → warm-start AUTO-surfaces the L0 RESUME board's last-touched section (+ index of the rest); /recall <project> to swap threads
   DAILY START (/start-work, once) → descend the ladder only as far as needed:
  L0 RESUME ─► L3 Open-Items(stale?) ─► L1 prev-day (_day.md · else flat) ─► L2 PROJECT_LOG/ARC/OPEN_ITEMS(if resuming) ─► /recall <lens>
       ▲                                                                                                              │
       │   one writer per artifact · no orphan logs · no read-only traps                                             │
       ▼                                                                                                              ▼
        SESSION END (/vault-push, any tab) → write top→down                                    DAY END (/wrap-up) → merge <sid>.md → _day.md + reconcile Open Items + commit
  L0 RESUME(overwrite touched section, set last_touched) → L1 <date>/<sid>.md → L2 PROJECT_LOG/proj (ARC on pivot; OPEN_ITEMS add/tick) → L3 append global inbox → cut: peel DECISIONS
```

---

## 4. Shape-agnostic readers over the mixed corpus

The handoffs corpus is **mixed by history**, and readers tolerate all three shapes without
migration:

- **51 legacy flat handoffs** `System/handoffs/<date>.md` (pre-folder era) — **frozen-valid**.
  Do NOT migrate them.
- **Folder days** `System/handoffs/<date>/` with per-session `<sid>.md` + a `_day.md` rollup — the
  current shape.
- **2 collision days** (`2026-06-29`, `2026-06-30`) that briefly had **both** a flat `<date>.md`
  AND a `<date>/` folder — folded down per `collision-fold-plan.md` (flat file's unique
  human-written Focus/Open-questions merged into `_day.md`, then the flat file `git rm`'d). After
  the fold these are ordinary folder days.

Reader contracts:
- **`/start-work` previous-day read:** prefer `System/handoffs/<date>/_day.md`; if that day has no
  folder, fall back to the flat `System/handoffs/<date>.md`.
- **`/recall`:** globs `System/handoffs/**/*.md` — picks up flat files, `<sid>.md`s, `_day.md`s,
  and weeklies uniformly.

---

## 5. Development & analysis work-types (session-loop skills)

- **`/dev-task`** (global) — no code work on a repo's main checkout. Every dev task gets its own
  git worktree (`~/code/<repo>-<slug>`, branch `type/<slug>`): scope → worktree → build → verify
  (`/verify` + `/code-review`) → PR → watch CI → squash-merge on remote → cleanup → write the
  `<sid>.md` handoff. Parallel sessions on the same repo get separate worktrees → zero collisions.
- **`/analysis`** (global) — SQL / API / business-number logic lives in your analytics
  lib (lib-first); scripts only import and orchestrate. Catch up (`/recall` + methodology) → scaffold
  a `scripts/<name>.py` on the lib → run (long jobs as tracked background tasks, real logfile) →
  persist script + a `research/<topic>.md` doc (numbers-first, caveats, cross-links) → `/vault-push`.

---

## 6. Domain automations & the daily-jobs engine (day-loop)

Anything that must run once per day is **declared, not hand-run**, in `System/daily-jobs.yaml`
(stdlib-parsed flat blocks; `freshness_hours` gates re-runs; optional `dow: N` runs only on
weekday N). `/start-work` runs `System/scripts/run-daily-jobs.sh` on the **first** session of the
day (guarded by the day marker `System/handoffs/<date>/_day-started.json`) and reports a status
table (✅ fresh / ▶ ran / ⚠ failed).

Current declared jobs + domain syncs (preserved from the keeper):
- **`aop-tracker-daily`** (engine, daily) — Referee Quality Tracker: Metabase scrape →
  `canonical.db` cache → Mixpanel funnels → compute → publish (this **is** the referral
  `canonical.db` refresh; freshness-gated).
- **`bonds-weekly-referral`** (engine, `dow: 2`) — Tuesday bonds weekly funnel →
  `bonds_weekly_latest.txt`; `/start-work` posts it to `#daily-bonds-updates` via the Slack MCP.
- **Monday Play Console sync** — `/start-work` (Mondays) reminds the user to run
  `play_console.py sync --weeks 1` (needs fresh cookies). Candidate to promote to a `dow: 1`
  engine job (see `daily-jobs-additions.md`); until then it's a `/start-work` reminder.

---

## 7. Hooks

| Hook | Role |
|------|------|
| `SessionStart` (`session-marker-hook.sh start`) | Create/refresh the active-session marker (§2.1). |
| `SessionStart` (warm-start) | Inject the L0 RESUME `last_touched` section + 1-line refs per other live thread; flag "▶ first session today — consider `/start-work`"; flag substantive unpushed sessions. |
| `Stop` (`session-marker-hook.sh touch`) | Bump the marker heartbeat + sync `pushed`. Every turn. |
| `Stop` (session-export) | Export the transcript (session-scoped, debounced). |
| `pre-commit` (`tools/hooks/pre-commit`) | Enforce the L0 pairing: a commit staging any `PROJECT_LOG.md` must also stage `RESUME.md`; a staged `RESUME.md` must carry a `last_touched` pointing at a real `## <project>` section. `--no-verify` for a deliberate log-only edit. |

---

## 8. Decisions locked
1. **L0 RESUME = per-project board** (2026-06-16) — one `## <project>` section; the deterministic
   `tools/resume_board.py` writer (called by `/vault-push`, never hand-edited) overwrites only the
   touched section, sets `last_touched`, and sweeps sections dormant >30d into a collapsed
   `## Archived` block. No clobber across parallel tabs. Enforced by the pre-commit hook.
2. **L1 handoffs = a per-day folder** — `System/handoffs/<date>/` with per-session `<sid>.md`
   (written by `/vault-push`) + a `_day.md` rollup (written by `/wrap-up` ONLY). The flat
   `System/handoffs/<date>.md` writer is **retired** (it collided with the folder). Legacy flat
   files stay frozen-valid; readers are shape-agnostic (§4).
3. **Weekly roll-up tier RETIRED (2026-07-01).** The materialized L2 weekly (`/week-review` →
   `handoffs/weekly/`, and `/weekly`) was removed as low-value. `/recall last week` computes on
   demand from `_day.md` + `PROJECT_LOG` slices. Friday `/wrap-up` still runs the *KB-consolidation*
   KB-consolidation pass (semantic discrepancy scan + KB promotion, run inline) — a distinct pass, not a roll-up.
4. **L2 = PROJECT — all `/vault-push`-owned, project-scoped:** `PROJECT_LOG.md` (history, every
   session) · `PROJECT_ARC.md` (throughline, pivots only) · `OPEN_ITEMS.md` (forward todos —
   add/tick/carry every session) · `decisions/` (ADRs, peeled session-end). Parallel-safe: each is
   project-scoped (one writer), so parallel tabs don't clobber. PROJECT_LOG format standard:
   `# Project Log` H1 · `## YYYY-MM-DD[ · sid · type][ — summary]` entries (newest-first) · **bold**
   sub-labels, never `###` for dates · count = `grep -cE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}'`.
   **Do not change header depth.**
5. **L3 = STATE (forward, global).** Project todos live in `Notes/<proj>/OPEN_ITEMS.md` (L2,
   `/vault-push`-owned). The GLOBAL `System/dashboards/Open Items.md` is cross-cutting / ops only:
   sessions **append** to `## Inbox (unsorted)` (tagged `<!-- sid:xxxx -->`); `/wrap-up` is the sole
   writer of its structured tables; `/vault-push` may tick-done items it resolved.
6. **DECISIONS = per-project** `Notes/<proj>/decisions/`, surfaced by `/recall decisions`.
7. **No PORTFOLIO view** — skipped as low-value paperwork.
8. **Worktrees mandatory** for code work; **lib-first** for analysis.
