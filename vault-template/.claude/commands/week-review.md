# /week-review — Materialize the Weekly Digest

Snapshot the week into durable digest docs (the **week** tier of the temporal hierarchy).
Weekly is computable live via `/recall last week [project]`; this command materializes a
curated, stable artifact (useful for a status report or a Monday catch-up).

Write the digest directly in an executive, stakeholder-ready tone: lead with outcomes
(shipped / decided / moved), then open threads, then next week. Concise and skimmable.

## Steps

### 1. Resolve the week
- Default = the current ISO week. Accept an arg (`/week-review 2026-W25`).
- ISO week id: `date +%G-W%V`. Compute the Mon–Sun date range for the header.

### 2. Gather the week's material (in range)
- Session handoffs: `System/handoffs/<date>/<sid>.md` for each date in range.
- Day rollups: `System/handoffs/<date>/_day.md`.
- Per project: the `### YYYY-MM-DD · …` entries in each `Notes/<project>/PROJECT_LOG.md` that
  fall in range (the temporal spine).
- Completed items this week from `System/dashboards/Open Items.md`.
- Optionally `qmd query "<themes>" -c sessions` to catch anything not in handoffs.

### 3. Write the global digest
- `System/handoffs/weekly/<YYYY-Www>.md` from `System/templates/weekly-digest.md`
  (scope: global). Highlights / Shipped / Decisions / Metrics moved / Carried-forward /
  Sessions-this-week. `mkdir -p System/handoffs/weekly` first.

### 4. Write per-project digests
- For each project active in range: `Notes/<project>/digests/<YYYY-Www>.md` (scope: <project>),
  same template, scoped to that project's entries. `mkdir -p` the digests folder.

### 5. Reindex
```bash
qmd update && qmd embed
```

### 6. Confirm
- "Week <YYYY-Www> digest written: global + N project digests." List the paths.

## Notes
- This does not replace `/wrap-up` (daily) — it's a weekly synthesis on top of the daily rollups.
- Run it whenever you want the stable artifact (commonly Friday/Monday); it's optional.
