# /maintain — Vault Maintenance

Run a health check on the vault.

Delegate this task to the **librarian** agent. The librarian will:
1. Audit frontmatter on all notes in `Notes/`
2. Check for broken wikilinks
3. Detect potential duplicates
4. Find orphaned notes (no inbound or outbound links)
5. Report vault stats (notes by category, by status, recent activity)
6. Flag issues and suggest fixes

Output a summary report.
