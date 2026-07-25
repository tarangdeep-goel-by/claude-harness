# NotebookLM — Usage Guide for Claude Code

## What It Is

Google NotebookLM gives source-grounded AI Q&A over your documents. Zero hallucination — only answers from uploaded sources with inline citations. Also generates audio overviews (podcasts), video summaries, reports, quizzes, and mind maps.

## When to Use It

| Use Case | Why NotebookLM over Vault Search |
|---|---|
| Deep-dive Q&A on a project | Source-grounded, cites exact passages |
| Onboarding on new domain/codebase | Audio overview = podcast explaining the docs |
| Stakeholder prep | Query across all project docs before a meeting |
| Sharing context with teammates | Share notebook link — they get the same grounded AI |

## Authentication

**Sessions last ~20 minutes.** Always check auth before operations.

```bash
# First time / re-auth (opens browser)
nlm login

# Check if still authenticated
nlm auth status
```

Auth auto-recovers in most cases (CSRF refresh, token reload, headless re-auth). Only run `nlm login` if commands fail with auth errors.

## Core Workflow

### 1. Create a Notebook (done automatically by /new-project)

```bash
nlm notebook create "My Project Notes"
# Save the notebook ID — use aliases for convenience:
nlm alias set my-project <notebook-id>
```

### 2. Add Sources

```bash
# Add a markdown file as text
nlm source add my-project --text "$(cat Notes/my-project/spec.md)" --title "Product Spec"

# Add a URL
nlm source add my-project --url "https://example.com/your-page"

# Wait for processing before querying
nlm source add my-project --text "..." --title "..." --wait
```

### 3. Query (Source-Grounded Q&A)

```bash
# One-shot query
nlm notebook query my-project "What were the key decisions about notification timing?"

# Follow-up (maintains conversation)
nlm notebook query my-project "How does this relate to the cohort strategy?" --conversation-id <cid>

# Query specific sources only
nlm notebook query my-project "Summarize the competitive landscape" --source-ids <id1,id2>
```

### 4. Generate Content

```bash
# Audio overview (podcast) — takes 1-5 min
nlm audio create my-project --confirm

# Check status
nlm studio status my-project

# Download when ready
nlm download audio my-project <artifact-id> --output my-project-podcast.mp3

# Other content types
nlm report create my-project --confirm
nlm slides create my-project --confirm
nlm mindmap create my-project --confirm
nlm quiz create my-project --count 10 --confirm
nlm video create my-project --confirm
```

### 5. Sync Project Docs (via /sync-notebook command)

```
/sync-notebook my-project-notes
```

This reads all project docs and pushes them to the NotebookLM notebook.

## Useful Commands

```bash
# List all notebooks
nlm notebook list

# List sources in a notebook
nlm source list my-project

# Get AI summary of a notebook
nlm notebook describe my-project

# Get AI summary of a specific source
nlm source describe my-project <source-id>

# Get raw content of a source
nlm source content my-project <source-id>

# Check stale Drive sources (need re-sync)
nlm source stale my-project

# Share notebook publicly
nlm share public my-project

# Share with specific person
nlm share invite my-project user@example.com --role reader

# Batch query across multiple notebooks
nlm cross query "What decisions were made about user retention?" --tags "growth"

# Tag notebooks for organization
nlm tag add my-project --tags "growth,q2,active"
nlm tag select --tags "growth"
```

## Aliases

Use aliases to avoid typing UUIDs:

```bash
nlm alias list                          # See all aliases
nlm alias set my-project <notebook-id>  # Create alias
nlm alias get my-project                # Resolve to UUID
nlm alias delete my-project             # Remove
```

## Tips

- **Always use `--confirm`** on create/delete commands to avoid interactive prompts
- **Use `--wait`** when adding sources before querying (ensures processing is done)
- **Poll status** for audio/video — generation takes 1-5 min: `nlm studio status <notebook>`
- **Use `--quiet`** to get just IDs for scripting
- **Don't use `nlm chat start`** — it opens an interactive REPL. Use `nlm notebook query` instead.
- **Tag notebooks** for batch operations: `nlm tag add <nb> --tags "project,quarter"`
- **Export reports** to Google Docs: `nlm export to-docs <notebook> <artifact-id>`
