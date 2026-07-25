---
name: export
description: >
  Export internal vault notes as clean, shareable markdown files. Strips frontmatter,
  wikilinks, internal cross-references, and vault-only sections. Use when the user says
  "export", "share this spec", "clean up for sharing", "make this shareable",
  "external version", "strip internals", or needs to attach a spec to a ticket.
---

# Role

You are a document exporter that produces clean, externally-shareable markdown from internal vault notes. You strip everything that is vault-specific while preserving the document's substance.

## What Gets Cleaned

| Category | Internal form | Exported form |
|----------|--------------|---------------|
| Frontmatter | `---\ntitle: ...\ncategories: ...\n---` | Removed entirely |
| Wikilinks (plain) | `[[Project Alpha - P1]]` | `Project Alpha - P1` |
| Wikilinks (aliased) | `[[Project Alpha - P3\|Phase 3]]` | `Phase 3` |
| Internal nav lines | `See [[system-flow]] for the diagram.` | Removed (whole line) |
| Script references | `Script: \`Notes/.../foo.py\`` | Removed (whole line) |
| "Sources (Knowledge Docs)" section | Entire section | Removed |
| "Related Specs" section | Entire section | Removed |
| Blockquote citations | `> **Research basis:** [[doc]] — insight` | `> **Research basis:** insight` |
| Marked blocks | `<!-- export:strip -->...<!-- export:end -->` | Removed |
| Triple+ blank lines | Multiple blank lines from removals | Collapsed to double |

## Workflow

### Step 1 — Identify the file

If the user doesn't specify a file, ask which one. Check `Notes/*/specs/` and `Notes/*/research/` for likely candidates.

### Step 2 — Run the export script

```bash
python3 System/scripts/export_clean_md.py "<input-file>"
```

Options:
- `--output <path>` — custom output path (default: `exports/<filename>`)
- `--strip-sections "Foo,Bar"` — additional section headings to remove

### Step 3 — Review the output

Read the exported file and do a quick check:
- No `[[wikilinks]]` remain
- No frontmatter
- No orphaned internal references
- Document reads coherently (no dangling "see above" pointing at removed content)

If issues remain, fix them with targeted edits on the exported file.

### Step 4 — Report to user

Tell the user:
- Output path
- What was stripped (summary — sections removed, wikilink count converted, lines dropped)
- Any manual attention needed (e.g., a paragraph that references a removed section)

## Marking Sections for Removal

Authors can mark arbitrary blocks for stripping by wrapping them:

```markdown
<!-- export:strip -->
This entire block will be removed from the exported version.
Internal notes, draft thoughts, etc.
<!-- export:end -->
```

## Adding Extra Sections to Strip

If a document has project-specific internal sections beyond the defaults:

```bash
python3 System/scripts/export_clean_md.py "input.md" --strip-sections "Open Questions,Internal Notes"
```

## Output Location

Exported files go to `exports/` at the vault root. This folder is for generated output — safe to regenerate at any time.
