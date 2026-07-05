# ADOPT_FROM_HISTORY — turn your last 30 days of Claude Code into a populated vault

**For: anyone moving to this harness with existing Claude history** — whether you've used **Claude
Code** OR (more likely) the **Claude desktop app / claude.ai chats** (the people we most want to move
to Claude Code). You just did the install + setup (real onboarding effort). This is the payoff:
instead of an empty vault, your Claude mines your *own* history and reconstructs your recent work
into a populated, `/recall`-able knowledge base — **so within one pass you see what the harness is
worth.** This is the inverse of starting blank.

**Kick it off — paste this to your Claude (in the seeded vault):**
> "Read `ADOPT_FROM_HISTORY.md` and build my vault from my last 30 days of Claude Code history —
> projects, KBs, arcs, decisions, people, memory. Show me what you reconstructed."

You (Claude) then run the procedure below. **Goal = a fast, visible win:** real project knowledge
bases that read like they'd been kept all along, demonstrated with live `/recall`. Be ambitious and
thorough — this is the moment that justifies the onboarding.

---

## Prereqs
- `install.sh` has run (vault seeded). Read **`System/docs/HOW_THIS_SYSTEM_WORKS.md`** first — it
  defines the target structure (`Notes/<project>/`, ADRs, KB contract) and the conventions you must
  follow. `qmd` installed (for the final index + the win demo).

### Sources — two kinds of history (use whichever you have; ideally both)
- **A · Claude Code** (local, no setup): transcripts in `~/.claude/projects/<dir>/*.jsonl`.
  Tools: `./catalog-sessions.sh 30` (the map) + `./read-session.sh <id>` (one session, tool-noise stripped).
- **B · Claude desktop app / claude.ai chats** (server-side — this is most people): there's no local
  cache, so get the **data export** → claude.ai → **Settings → Privacy → Export data** → you'll get an
  email with a zip → unzip → **`conversations.json`** (and `projects.json`). Web, desktop, and cowork
  all write to the same account, so this one export covers them all.
  Tools: `./catalog-chats.sh conversations.json 30` + `./read-chat.sh conversations.json <id|name>`.
  (Anything not in the account export can't be mined locally — note that gap if it matters.)

## Phase 1 — Map your history (fast)
1. Build the map from whatever you have:
   - Claude Code → `./catalog-sessions.sh 30` → `session-catalog.md`
   - claude.ai/desktop export → `./catalog-chats.sh conversations.json 30` → `chat-catalog.md`
   Each lists every recent item with its **title** and **opening message** — your triage map.
   **Sanity-check the counts.** If the chat catalog says "0 conversations," your export is older than
   the window (exports lag hours–days) — widen it: `./catalog-chats.sh conversations.json 365`.
2. **Cluster into real projects — across BOTH sources.** Titles group themselves (e.g. "Implement
   bonds reward comms", "Resolve referrals CX", a "Referral funnel deep-dive" chat → one *referral*
   project; backend refactors → their repo's project). A working-dir or a single chat is a hint, not
   a project — merge related sessions + chats into the same project.
3. Present the proposed project list to the user (one line each: name + #items + date span) for a
   quick thumbs-up. Cheap, and it makes the reconstruction feel real immediately.

## Phase 2 — Deep-read the high-signal sessions
For each project, pick its **richest 3–8 items** (longest / most-decisive by title) and read them in
full — `./read-session.sh <id>` for Claude Code sessions, `./read-chat.sh conversations.json <id|name>`
for claude.ai chats (both strip the noise to plain human/Claude prose). Extract: what the project
*is*, what was decided and why, what shipped, what's still open, and recurring **people / metrics /
products / tools**. Skim the rest by title. Don't read everything end-to-end — sample the signal.
Note the session/chat id behind each fact (you'll cite it).

## Phase 3 — BUILD the artifacts (the win)
**First, check what already exists.** A returning user's vault may NOT be empty (you might have a few
notes already, and the sessions themselves often reference ADRs by number — e.g. "per ADR 0013").
So, per project:
- If `Notes/<project>/` already exists → **merge into it, never clobber.** Append to PROJECT_LOG;
  extend (don't overwrite) README/ARC/KB.
- For `decisions/` → **continue NNNN numbering from the highest existing ADR.** Never restart at
  0001 and never renumber existing ADRs — sessions cite them by number. If a session references an
  ADR number you can't find, create a stub for it and flag `> [!verify]`.

Then, for each project, create/extend a populated `Notes/<project>/` from `System/templates/` —
**written from the history, not stubbed.** This is the deliverable, not a digest:
- **`README.md`** — what it is, current status, key links. Real, current.
- **`PROJECT_ARC.md`** — the throughline you can see across the sessions: north-star, the phases /
  pivots, the current frontier. This is what makes future `/recall` feel like memory.
- **`PROJECT_LOG.md`** — **back-dated** entries, one per significant session (date from the catalog):
  what was done, decisions, outcomes, and the `session id` it came from. This reconstructs your real
  timeline — the spine of the vault.
- **`KNOWLEDGE_BASE.md`** — durable fundamentals only (what it IS + how it works: mechanics, rules,
  constraints, key concepts). **No metrics, no status** (those live in `research/` / `methodology` /
  `PROJECT_LOG`). The KB links out. Synthesize it from what the sessions taught.
- **`decisions/NNNN-<slug>.md`** — every clear decision you found → an ADR (context / decision /
  rationale / consequences). Isolating rationale here is what makes `recall decisions <topic>` work.
- **`research/<topic>.md`** — findings/analyses worth keeping; cite the source session + date.
Follow **HOW_THIS_SYSTEM_WORKS §7**: link entities, frontmatter (`categories/subjects/status/dates`),
the KB contract.

## Phase 4 — Cross-cutting entities
Recurring **people** → `People/<Name>.md`; recurring **metrics / products / tools** →
`Glossary/{metrics,products,tools}/<name>.md` (with `aliases:` for recall). Wikilink them
(`[[Name]]`, `[[metric]]`) across the notes you just wrote. This is what turns a pile of notes into a
connected graph.

## Phase 5 — Memory & open items
- **`Meta/memory.md`** — infer and write who you are, your team, your scope, and recurring
  preferences/working-style that show up across sessions. (This is the auto version of `/onboard`.)
- A few `~/.claude/projects/<vault-slug>/memory/*.md` files for durable facts/feedback that recur
  (one fact per file, with the frontmatter format) + update `MEMORY.md`.
- **`System/dashboards/Open Items.md`** — unfinished threads / TODOs / "next: …" surfaced across the
  recent sessions, so day 1 already has your real backlog.

## Phase 6 — Index, then SHOW the win
1. `qmd update && qmd embed` — index the reconstructed vault.
2. **Demonstrate it.** Run 2–3 `/recall` queries on the reconstructed work and show the output, then
   present a one-screen recap:
   > "From your last 30 days I reconstructed **N projects** — `<names>`. Logged **M decisions** as
   > ADRs, **K** people/metric/tool notes, and **P** open items. Ask `/recall <anything>` — e.g.
   > `/recall last week <project>` or `recall decisions <topic>`."
   That recap *is* the payoff: the harness already knows your work.

## Guardrails (so the win is real, not hollow)
- **Cite a session/chat id on every factual sentence.** Not "behind each fact" loosely — literally
  every claim traces to an id. If you can't cite it, it's an inference: mark `> [!verify] reconcile:`
  and don't assert it.
- **Carried numbers are CLAIMS, not ground truth.** Any figure in a transcript (₹ amounts, %, counts)
  is Claude's *past output* — once-removed from the DB, and the sessions themselves often say
  "re-verify these." Never present a reconstructed number as validated. Write it as
  "per session `<id>`: ~X (re-verify)" — especially before it goes in a deck or a decision.
- **Never invent.** If the history doesn't say it, don't write it. Framing ≠ fact — if you're
  inferring a decision/rationale from how something was discussed, flag it as an inference.
- **Additive + de-dup** — build on the seeded scaffold and any existing notes; don't delete or
  clobber (see Phase 3's existing-vault rule); continue ADR numbering.
- **Cap the scope.** Don't over-build: take the **top ~5 projects by sustained work**; the long tail
  of one-off sessions contributes context, not its own project. `log()`/note what you skipped.
- Quality bar: a teammate (or future you) could `/recall` any recent project and get real, *cited*
  context — and know which numbers still need DB re-verification.
