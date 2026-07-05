# /wrap-up — End of Day Audit & Triage

The **day-level** end bookend (complement of `/start-work`). Wrap up the day with a
collaborative audit. As the day's single writer of shared aggregates, `/wrap-up` rolls up
all of the day's session handoffs and reconciles the Open Items inbox.

## Steps:

### 0. Roll up the day's session handoffs
- Look in `System/handoffs/YYYY-MM-DD/` for the per-session files (`<sid>.md`) written by
  `/vault-push` during the day.
- Synthesize them into `System/handoffs/YYYY-MM-DD/_day.md` (the day rollup):
  - **Sessions today** — one line each: `<sid8> · project · type · status · goal`.
  - **Shipped / decided** — merged across sessions.
  - **Open threads** — union of all sessions' open threads.
  - **Where each project stands** — grouped by project.
- If any session was substantive but has no handoff file (check `~/vault/logs/active-sessions/`
  for `pushed:false`), flag it: "Session `<sid>` never ran /vault-push — capture it now?"

### 1. Process all unprocessed recordings
- Scan today's `Daily/YYYY-MM-DD/` folder
- Check every .m4a file has a corresponding processed meeting note (.md)
- For any unprocessed recordings:
  1. Run `bash ~/Documents/vault-work/System/scripts/transcribe-whisperx.sh <recording.m4a>` to generate the transcript with speaker diarization
  2. Invoke the **transcriber** skill to create a structured (detailed, embeddable) meeting note
  3. Ask the user for meeting type and attendees if not obvious from the transcript
- Continue until all recordings are processed

### 2. Review meeting note questions
- Read `Meta/agent-messages.md` for any messages from Transcriber about questions for review
- For each flagged meeting note:
  - Read the `## Questions for Review` section
  - Present the questions to the user
  - Incorporate answers back into the relevant sections of the meeting note
  - Check off answered questions: `- [ ]` → `- [x]`
  - If a question led to a new insight or correction, update the note body
- Mark agent messages as resolved (⏳ → ✅)

### 3. Process docs inbox
- Run `bash System/scripts/convert-docs.sh` to convert any raw files (PDF, DOCX, PPTX, etc.) to Markdown
- For each converted file, ASK the user:
  - "What is this document? Which project does it relate to?"
  - Move the original file + converted .md to `Notes/<project>/supporting_docs/`
- If no files in docs-inbox, skip this step

### 4. Compile new supporting docs
- For each project that received new files in `supporting_docs/` today (from step 3 or earlier):
  - Check `Notes/<project>/.compile-state.json` for uncompiled docs
  - If uncompiled docs exist, ask the user: "**<project>** has N new docs in supporting_docs/. Compile into research notes?"
  - If yes, run the **compiler** skill on that project
- If no new supporting docs across any project, skip this step

### 5. Triage the scratchpad
- Read today's daily scratchpad `Daily/YYYY-MM-DD/YYYY-MM-DD.md`
- For each rough note/item, ASK the user clarifying questions:
  - "You wrote X — can you give me more context?"
  - "Is this a todo, FYI, or decision?"
  - "Which project does this relate to?"
- After user answers, formalize each item:
  - **Todos** → add to `System/dashboards/Open Items.md`
  - **FYIs** → enrich with context, keep in daily note
  - **Decisions** → create a proper decision note in the relevant project's `decisions/` folder
  - **People info** → update `Meta/memory.md` team/stakeholder section

### 6. Reconcile the Open Items ledger (sole structured writer)
- Read `System/dashboards/Open Items.md`.
- **Reconcile the inbox:** for each bullet under `## Inbox (unsorted)`:
  - Dedupe against existing **Active** items; if new, move it into the **Active** table (fill
    Source/Owner/Added from the `<!-- sid:xxxx -->` tag + today's date).
  - Drop the bullet from the inbox once sorted. Leave the inbox empty (keep the header + the
    `<!-- new items appended below this line -->` marker).
- Add any other new items surfaced during triage.
- Ask user: "Any items completed today?" → move to **Completed**.
- Carry everything else forward. This is the only command that edits the structured tables.

### 7. Update memory
- If new people, tools, or processes were learned today, update `Meta/memory.md`

### 8. Weekly consolidation — Fridays only
Run this step **only on Fridays** (or if the user explicitly asks for a weekly consolidation /
it's the last working day of the week):
```bash
[ "$(date +%u)" = "5" ] && echo "FRIDAY — run weekly consolidation" || echo "not Friday — skip step 8"
```
If it's Friday:
1. **Mechanical find first** — run `/vault-audit last 7 days` to produce the issue list
   (skills firing, pushes happening, broken links, missing frontmatter, orphans).
2. **Hand off to the librarian** — delegate to the **librarian** agent (Agent tool) for the
   weekly consolidation, passing the vault-audit findings. The librarian will: run the semantic
   discrepancy candidate-finder (`System/scripts/discrepancy-scan.py`) and adjudicate its
   suspects (metric drift, decision/status conflicts, note↔transcript fidelity, entity
   co-mentions); **promote the week's meeting-note alignments/discoveries into the KB**; collate
   the week's work into the right `research/` docs; reconcile contradictions; update each
   project's `KNOWLEDGE_BASE.md` (links out, no metrics/status); enforce the doc-type contract;
   fix link/frontmatter issues; and write a consolidation report to
   `Daily/YYYY-MM-DD/librarian-weekly-<YYYY-Www>.md`.
3. **Surface the librarian's "Needs your decision" list** to the user — resolve ambiguous
   merges/contradictions interactively; the librarian never auto-deletes or merges those.

### 9. Create handoff note
- Create `System/handoffs/YYYY-MM-DD.md` with:
  - What was accomplished today
  - Decisions made
  - Open questions
  - What to focus on tomorrow

### 10. Append audit to daily note
Append to `Daily/YYYY-MM-DD/YYYY-MM-DD.md`:
```
## Daily Audit

### Meetings Captured
- [list of processed meetings]

### Docs Compiled
- [list of research notes created/updated, or "none"]

### Scratchpad Items Triaged
- X items formalized (Y todos, Z FYIs, W decisions)

### Open Items Added
- [new items]

### Memory Updates
- [what was updated]
```

### 11. Git commit today's changes
- Stage all changes in the vault:
  ```bash
  cd ~/Documents/vault-work && git add -A
  ```
- Create a commit with a summary of the day:
  ```
  daily: YYYY-MM-DD — X meetings, Y notes, Z decisions
  
  Meetings: [list of meeting topics]
  Notes triaged: [count]
  Decisions: [list]
  Open items: [added/completed counts]
  ```
- This ensures every day's work is versioned and recoverable
- Do NOT push to remote — just local commits
