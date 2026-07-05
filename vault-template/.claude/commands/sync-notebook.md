# /sync-notebook — Sync Project to NotebookLM

Sync a project's documents to its NotebookLM notebook for source-grounded Q&A and audio overviews.

## Steps:

### 1. Identify the project
- If `$ARGUMENTS` provides a project name, use it
- Otherwise, ask: "Which project do you want to sync to NotebookLM?"

### 2. Find the NotebookLM notebook
- Check the project's `Notes/<project>/README.md` for a NotebookLM notebook ID/link
- If no notebook exists, create one: `nlm notebook create "<Project Name>"`
- Save the notebook ID in the README

### 3. Gather project documents
Collect all markdown files from the project folder:
```bash
find Notes/<project>/ -name "*.md" -not -name "CLAUDE.md" -not -name ".gitkeep"
```

Also check for documents in:
- `Notes/<project>/supporting_docs/` (PDFs, etc.)
- Related meeting notes from `Daily/` that reference this project

### 4. Sync sources to NotebookLM
For each document, add it as a source to the notebook:
```bash
# For text/markdown files — use text source
nlm source add <notebook-id> --text "$(cat <file>)" --title "<filename>"

# For files on Google Drive (if uploaded via upload_to_gdrive.sh)
nlm source add <notebook-id> --drive "<drive-url>"
```

### 5. Optionally generate audio overview
Ask the user: "Want me to generate an audio overview (podcast) for this project?"
If yes:
```bash
nlm studio create <notebook-id> audio --confirm
```

### 6. Report
- How many sources were synced
- Link to the NotebookLM notebook
- Whether audio overview was generated
