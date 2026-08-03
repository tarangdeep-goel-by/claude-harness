# ADOPT_EXISTING_DATA — import an adopter's existing local data into the vault

**For: everyone adopting this harness.** Not everyone has an existing `qmd` index, and not everyone
keeps an Obsidian vault — but **everyone has files and a working directory** where they already do
their work. That directory is the one universal source, and the old runbook never looked at it: it
mined Claude *history* (`ADOPT_FROM_HISTORY.md`) but ignored the files already on disk. **This step
imports the adopter's working directory into the vault so `/recall` sees their real work — not the
empty scaffold.**

The seeded vault starts empty and `setup-work-machine.sh` will (re)build the `qmd` index from
scratch. Cleaning + rebuilding the index is fine — **as long as we first import the real files into
the vault and then re-embed.** What is NOT fine is finalizing the index while the adopter's actual
work still lives outside it. Run this **first** (files on disk), then `ADOPT_FROM_HISTORY.md`
(Claude history) — together they give a full populated vault.

**Kick it off — paste this to your Claude (in the seeded vault):**
> "Read `ADOPT_EXISTING_DATA.md`. Ask me where I currently work, find my existing notes/data, and
> import what makes sense into the vault before the qmd index is finalized."

You (Claude) then run the procedure below. **Never move or delete from the source — copy only.**

---

## When this runs

Between "dependencies installed" and "qmd index finalized" in `SETUP_FOR_CLAUDE.md` — the import must
land before the first `qmd embed` so the index covers it. (If the index was already built, that's
recoverable — the re-embed at the end picks up the imported data.) **If** the adopter happens to have
an existing `~/.config/qmd/index.yml`, treat it as a bonus map of where their data already lives and
read it before anything overwrites it (`setup-work-machine.sh` backs it up first) — but most adopters
won't have one, so never depend on it. The working directory is what you always import.

## Phase 0 — Ask for the working directory (always), then augment

1. **Ask — the one question you must always ask:** *"What directory do you do your work in?"*
   Everyone has one; it is the universal source. Also ask if they keep notes somewhere else (an
   Obsidian vault, a separate notes folder) so nothing is missed. **The working directory is the
   anchor — you import it regardless of whether they have qmd or Obsidian.**
2. **Augment with auto-discovery (bonus, never required):**
   - **If `qmd` is installed** and `~/.config/qmd/index.yml` exists, read it — every `collections:`
     entry is a real directory of their data, so it maps where the good stuff already sits (`qmd
     collection list` for counts). Most adopters won't have this; don't wait for it.
   - Obsidian vaults: directories containing `.obsidian/` (`find ~ -maxdepth 4 -name .obsidian -type
     d`, skipping caches/node_modules).
   - Other dense markdown/doc trees: `~/Documents`, `~/notes`, `~/Desktop`, a Logseq/Zettelkasten tree.
3. **Look inside the working directory and classify** — it is usually a *mix*: docs/notes (markdown,
   text, PDFs, specs), code, configs, and junk (build output, caches, `.git`, `node_modules`). Report
   one line per candidate source: path · kind · file count · rough date span. This is the triage map.

## Phase 1 — Propose an import plan (get a thumbs-up)

Present a short plan, then wait for confirmation. **A working directory is a mix — default to
importing its *knowledge* (docs, notes, specs, text/PDF) and leaving code repos, build output, and
caches out, unless the user says they want code searchable too.** Pick a strategy per source:

- **COPY into the seeded vault** (default). Best for loose notes and small collections. Map:
  - project-shaped folders → `Notes/<project>/` (preserve internal structure)
  - dated/journal notes → `Daily/YYYY-MM-DD/` where a date is inferable, else `Notes/imported/`
  - everything else → `Notes/imported/<source-name>/`, structure preserved
- **POINT the index at it in place** (don't duplicate). Best when the source is *already* a
  well-structured Obsidian vault they'll keep editing there. Add it as its own `qmd` collection in
  `index.yml` instead of copying — one source of truth, no divergence. (Note it so the vault's
  `CLAUDE.md`/README records where that collection physically lives.)
- **SKIP.** Caches, exports, binaries, anything not worth searching. Say what you're skipping and why
  — silent omission reads as "imported everything."

State the file counts moving and the destination for each, so the result is verifiable.

## Phase 2 — Import (non-destructive)

- **Copy, never move.** `rsync -a --ignore-existing <src>/ <dst>/` (or `cp`) — the source stays intact.
- **De-dup against the seeded scaffold** — don't overwrite template files with the user's; and if the
  same note exists in two sources, keep one and note the collision.
- **Preserve frontmatter and structure.** Don't reformat their notes. If they lack frontmatter and a
  project needs it, add minimally per `System/docs/HOW_THIS_SYSTEM_WORKS.md` §7 — don't rewrite prose.
- If a source is a live Obsidian vault you chose to POINT at (not copy), add its collection to
  `index.yml` now (see Phase 3) rather than copying files.

## Phase 3 — Reconcile qmd (the safe clean + rebuild)

Cleaning the index is explicitly OK **because we re-embed** — but make it non-silent and verifiable:

1. **Snapshot the before-state:** `qmd collection list` — record each collection + file count. If
   `index.yml` already exists, confirm it's backed up (`setup-work-machine.sh` writes a timestamped
   `.bak`; if you're doing this by hand, copy it aside first).
2. **Write the final `index.yml`** so it covers (a) the standard vault collections and (b) any
   "POINT at in place" sources from Phase 1. Do not silently drop a collection the adopter had —
   either it's now covered by an imported/pointed collection, or you list it and confirm with them.
3. **Rebuild:** `qmd update && qmd embed`.
4. **Verify it grew, not shrank:** `qmd collection list` again — total indexed docs should be
   **≥ the before-count plus what you imported**. If it dropped, a source was lost — stop and
   reconcile before moving on. Run one `qmd query` over imported content to prove it's searchable.

## Phase 4 — Hand off

- Now run **`ADOPT_FROM_HISTORY.md`** for the Claude-history layer (sessions + claude.ai export).
  Existing files + history together = the populated vault. It de-dups against what you just imported.
- Then **`/onboard`** to fill `Meta/memory.md`.
- Finish with the SETUP_FOR_CLAUDE verify step and a live `/recall` over freshly-imported content —
  that demo is the proof the import worked.

## Guardrails

- **Copy, never move or delete from source.** The adopter's original data is untouched.
- **Additive + de-dup** — build on the seeded scaffold; don't clobber template files or their own.
- **A clean index is fine; a *shrunk* index is a bug.** Always snapshot counts before and verify
  after. Never let a collection disappear silently — that's the exact failure this doc exists to fix.
- **Ask before pointing at a large in-place source** (whole `~/Documents`) — scope it to what's worth
  searching, or the index balloons with noise.
- **Don't invent structure.** If you can't tell what a folder is, put it under `Notes/imported/` as-is
  and flag it for the user to sort later, rather than guessing a project taxonomy.
