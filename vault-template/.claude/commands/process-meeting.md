# /process-meeting — Process Meeting Recording or Transcript

Process a meeting recording (audio file) or transcript into a structured meeting note.

## Step 1: Determine Input

The user will provide one of:
- **Audio file path** (m4a, mp3, wav, etc.) → transcribe first, then process
- **Pasted transcript text** → process directly
- **Transcript file path** (.txt) → read and process

### If audio file:
Run the transcription script (WhisperX with diarization):
```bash
bash ~/Documents/vault-work/System/scripts/transcribe-whisperx.sh "<audio-file-path>"
```
This runs WhisperX with speaker diarization and outputs a JSON + readable .txt transcript with speaker labels.

Fallback (faster, no diarization):
```bash
bash ~/Documents/vault-work/System/scripts/transcribe.sh "<audio-file-path>"
```

## Step 2: Invoke the Transcriber Skill

Invoke the **transcriber** skill with the transcript text. Transcriber produces *detailed,
embeddable* knowledge documents (not gist/minutes) — they are indexed and surfaced later by
`/recall`, so depth is the point. The transcriber will:

1. **Intake interview** — ask for (skip what's already provided):
   - Meeting date (default: today)
   - Meeting type (standup, 1-on-1, brainstorm, architecture/KT, sprint planning, review/retro)
   - Attendees (names and roles)
   - Related project/initiative
   - Transcript source

2. **Apply meeting-type-specific extraction** — each type has different depth and focus

3. **Create structured note** in `Daily/YYYY-MM-DD/` using the matching template
   - File name: `meeting-<topic>.md` (e.g., `meeting-sprint-planning.md`)
   - If the user specifies a project, also link or copy the note to `Notes/<project>/meetings/`

4. **Update daily scratchpad** — link the meeting in today's `Daily/YYYY-MM-DD/YYYY-MM-DD.md`

5. **Capture action items** — append significant tasks to the `## Inbox (unsorted)` of `System/dashboards/Open Items.md` (reconciled by `/wrap-up`)

## Step 3: Project Linking (Optional)

If the user specifies which project the meeting relates to:
- Create a link or copy of the meeting note in `Notes/<project>/meetings/`
- Ensure the frontmatter includes the project reference
- If the project's `meetings/` folder doesn't exist, create it

If no project specified, the meeting note stays only in `Daily/YYYY-MM-DD/`. It can always be linked later.
