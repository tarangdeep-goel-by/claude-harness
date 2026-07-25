# <WORKBOOK NAME> — build (single source of truth)

> Template for any Google Sheet deliverable. Copy to `Notes/<project>/scripts/<NAME>_WORKBOOK.md`.
> The vault standard (CLAUDE.md › Deliverable Standards): **lead with the answer, then method, then
> evidence**; mandated tab order **README → Summary → Methodology → Trend → deep-dives**; every tab
> self-explanatory; ONE generating script + ONE collating doc (this file); mirror live edits to the script.

- **Live sheet:** id `<SHEET_ID>`
- **Window / headline:** `<window>` — `<the one-line answer + key numbers>`
- **Source:** `<DBs / tables / APIs>`. READ-ONLY. Needs `<creds / VPN>`.
- Run with `<venv python>` from this `scripts/` dir.

---

## Rebuild end-to-end
```bash
PY=<venv python>
$PY <main_pipeline_script>.py <args>     # builds <N> of <M> tabs in one run
# <any separate steps, e.g. a different-cohort tab>
# publish to your sheet via your own Sheets/Drive workflow
```

## Pipeline — who builds what
| Script | Produces / owns |
|---|---|
| `<orchestrator>.py` | Orchestrator → README · Summary · Methodology · Trend · <deep-dives>. Calls the builders below. |
| `<builder>.py` | <which tabs / which logic> |
| `<repull>.py` | Re-pulls + persists any cached source (`--pull`). |
| … | … |

## Data / caching (pulls must be deterministic)
- All pulls persist to `~/.cache/<workbook>/`; compute reads the **cache**, not the live source — re-runs reproduce.
- Cached data is **NOT committed** (`.gitignore`d, regenerable). The **pull script is durable** + re-runnable.
- If the cache is missing the pipeline **re-pulls or skips gracefully** (never hard-fails / never depends on committed data).

## The tabs
| Tab | What it shows | Basis |
|---|---|---|
| README | Front door: window, sources, why-counts-moved, tab guide | — |
| Summary | Exec Summary (the answer) + the cuts | headline |
| Methodology | Definitions, universe boundary, exclusions, caveats | — |
| Trend | Time series + coverage caveats | headline + denom |
| <deep-dive> | <…> | <headline / broader> |

## Methodology / key decisions
- <headline universe + why> (link the ADR)
- <key filter / definition choices>
- <basis caveats: which tabs are on a broader/different basis — "do NOT reconcile line-by-line">
- <coverage boundaries>

## <YYYY-MM-DD> changes
- <what changed this session>

## Open / deferred
- <…>

Related: <ADRs, methodology, feedback memos, memories>.
