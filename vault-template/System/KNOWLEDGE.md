---
title: "Knowledge — the semantic-memory law (how the knowledge store mutates)"
type: system
created: 2026-07-02
updated: 2026-07-02
---

# Knowledge (semantic memory)

Peer to `System/CONTINUITY.md`. Two memory systems, two laws:

- **`CONTINUITY.md` governs EPISODIC memory** — *what happened, when.* Append-only, timestamped,
  one writer. Clean by construction: you never rewrite history.
- **This doc governs SEMANTIC memory** — *what is true / what we decided.* Mutable, deduplicated,
  edited in place. The only layer you change in situ — so the only one that drifts.

The relationship is a **consolidation pipeline**: `episodic events → (/vault-push decision peel +
Friday /wrap-up KB-consolidation) → semantic knowledge`. Creation & routing of semantic facts
(two-tier model, "where a new finding goes") are governed by `Notes/CLAUDE.md` — this doc is the
missing chapter: **mutation.** Evidence and the standing named fix-list:
`Notes/vault-infra/research/semantic-memory-audit.md`.

---

## The law

Episodic cleanliness comes from one law (*every tier is a matched WRITE↔READ pair with exactly
one writer; append-only*). Semantic cleanliness needs its mutation twin:

> **Every fact has one OWNER, a declared FRESHNESS, and — when it changes — a bidirectional
> SUPERSESSION link. The RECONCILIATION that detects violations of these is consumed on a fixed
> cadence.**

Four forbidden failure modes (the semantic twins of episodic "write-only = dead cost / read-only =
stale trap"):

| Failure | What it looks like | Why it drifts |
|---|---|---|
| **Restatement** | the same fact fully stated in 2+ places, none a pointer | one copy gets updated, the others silently go stale |
| **Silent supersession** | a changed decision overwritten, or left standing unmarked | `/recall` surfaces the dead ADR beside the live one, no signal which won |
| **Unbounded freshness** | a fact with no verify horizon | a stale fact is presumed current forever |
| **Dead detector** | reconciliation output nobody reads | the immune system exists but never runs (this is `discrepancy-scan` today) |

---

## Owners — who is authoritative for each fact-type

One owner per fact. Everyone else **points**, never restates. (Routing a *new* finding to its
owner is the `Notes/CLAUDE.md` decision tree — not restated here.)

| Fact-type | Authoritative owner | Everyone else |
|---|---|---|
| Project rule / policy / eligibility / caps / engine quirk | `KNOWLEDGE_BASE.md` (live experiments → `EXPERIMENTS.md`) | link to the §section |
| Derived number (cohort size, ROAS, rate, total) | the canonical **script** (`scripts/README.md` registry) | cite `<script.py> @ <cache_date>` |
| A decision + its why | the **ADR** (`Notes/<proj>/decisions/`) | link the ADR |
| Person / metric / product / tool | `People/` or `Glossary/` note (with `aliases:`) | `[[wikilink]]` |
| Interpretation / judgment / recommendation | the canonical **research doc** for the topic | cite it |
| Cross-project operational knowledge (tool gotchas, API quirks, prefs, pointers) | **auto-memory** (`~/.claude/.../memory/`) — kept SHORT, loads every session | one-line pointer, not a copy (Pillar 5) |

---

## Pillar 1 — one ADR shape (supersession must be expressible)

Root cause of "1/71 marked": **~30 ADRs use a lightweight `date-slug` template with no `status:`
field at all** — supersession is structurally unexpressible on them.

- **One template** for every ADR file: `System/templates/decision-record.md`. It carries the
  closed status enum (`proposed | accepted | superseded | reversed` — no other values), plus
  `supersedes:` and `superseded_by:`.
- **The escape hatch for a minor call is a bold `Decision:` line in the PROJECT_LOG entry — NOT a
  lighter ADR file.** If it deserves a file, it deserves the full shape.
- **Supersession is bidirectional:** the new ADR sets `supersedes: <old>`; the old ADR flips to
  `status: superseded` and sets `superseded_by: <new>`. A decision overtaken by *reality* (no
  successor ADR) flips to `superseded`/`reversed` and points at the KB section that now owns the
  truth.
- **Lineage without retirement:** when an ADR *cites / formalizes / refines* an earlier one without
  retiring it (e.g. a policy ADR formalizing a finding note), use `builds_on:` — the target keeps its
  status. `supersedes:` is only for retirement; don't overload it.
- **Follow-up (deferred to OPEN_ITEMS):** backfill `status:` onto the ~30 legacy lite ADRs so the
  field exists before drift can be marked.

## Pillar 2 — enforced supersession integrity (mechanical, pre-commit)

Split by what a hook can actually know:

- **Hook-enforceable (in `tools/hooks/pre-commit`, the existing L0-pairing gate):** a staged
  ADR must (a) carry a `status:` from the closed enum, (b) if it sets `supersedes: X`, then `X`
  must exist and carry `status: superseded` — links resolve or the commit fails. A
  `supersedes:`/`builds_on:` value is treated as an ADR reference (and integrity-checked) **only
  when it names one** — a `NNNN-`/`YYYY-`-prefixed stem or a `[[wikilink]]`. Free-text describing
  a *non-ADR* thing it replaced (e.g. a closed program, an earlier draft) is allowed and skipped.
- **NOT hook-enforceable:** whether a new ADR *silently contradicts* an old one it didn't declare.
  Semantic — cheap hooks can't judge it. That is Pillar 4's job: the scan surfaces candidates, a
  human declares the link, then Pillar 2 keeps the declared link honest.

Two layers, same as the lib-drift enforcement stack: hook catches the mechanical, scan surfaces
the semantic.

## Pillar 3 — declared freshness (verify horizon → surfaced queue)

- Every `KNOWLEDGE_BASE.md` / `EXPERIMENTS.md` carries `verify_by: YYYY-MM-DD` (or `freshness_days:`)
  in frontmatter. Default windows: **high-churn projects (referral, comms) 21d; stable 45–60d.**
- `/start-work` reads it and surfaces KBs past their horizon in a **stale-knowledge queue** —
  same treatment as the existing Open-Items `updated:` staleness flag and the daily-jobs
  `freshness_hours` gate. Re-verifying resets `updated:`/`verify_by`.
- Per-fact `(as of YYYY-MM-DD)` markers stay encouraged for volatile individual facts; the doc-level
  horizon is the floor.

## Pillar 4 — consumed reconciliation (no dead detectors)

`discrepancy-scan.py` exists, is wired into Friday `/wrap-up`, and has **never produced a consumed
artifact** — a dead detector, which the law forbids. Fix it or delete it:

- It writes to a **fixed path** (`System/dashboards/knowledge-drift.md`); Friday `/wrap-up`
  **reads that file and acts** on it inside the KB-consolidation step (promote / mark superseded /
  compress / re-verify). WRITE↔READ pair closed.
- Its job = the automated version of the manual audit we just ran: (a) ADRs superseded-but-unmarked
  (topic-cluster + recency), (b) memory↔KB overlaps/conflicts, (c) KBs past `verify_by`.
- If we will not wire the read side, **delete the script** — an unconsumed detector is dead cost.

## Pillar 5 — auto-memory ↔ KB boundary (memory points, KB owns)

Two semantic stores overlap; the old "mirror-rule" (update both) *creates* the restatement failure.
Replace it:

- **Auto-memory** = cross-project, cross-session operational knowledge that must auto-load into
  *every* session (who the user is, tool gotchas, API quirks, working-style feedback, pointers).
  Optimized to be SHORT — it loads every session (the MEMORY.md truncation was this rule being
  violated).
- **Vault KB** = project-scoped codification. **Owns** project rules/facts.
- **The boundary:** a project fact is owned by the KB. Auto-memory may carry a **one-line pointer**
  to it, never a full restatement. A memory entry that fully duplicates a KB rule is a bug →
  compress to a pointer.
- **"KB is authoritative" means "the place to fix," not "assume it's current."** If memory is the
  fresher source (it happens), fix the **KB first** (rule book leads), then re-point memory.
- Normalize the frontmatter shape to the nested `metadata:` form (low-priority cleanup; both shapes
  parse today).

---

## Implementation status

Law-as-of-today (governs how we work now): the owner map, the one-ADR-shape rule + escape hatch,
the memory-points-KB boundary, and "no dead detectors." **Build follow-ups (→ `OPEN_ITEMS.md`,
`/vault-push`-owned):** backfill `status:` on ~30 lite ADRs · add the pre-commit link-integrity
check · roll `verify_by` onto the 4 KBs · wire `discrepancy-scan` output→`/wrap-up` read (or delete)
· add `superseded_by:` to the template (done) · execute the standing named fix-list in the audit
doc (M1/SCC window escalated to eng first — a possible live code/FAQ bug, not doc drift).
