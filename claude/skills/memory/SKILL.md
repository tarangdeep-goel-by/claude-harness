---
name: memory
description: "Memory corpus quality rollup. /memory health reports capture/approval/utilization/hook-health; /memory review proposes harness tweaks."
user_invocable: true
---

# /memory — Memory Corpus Quality

Read-only rollup of how the memory corpus is doing: are candidates being captured,
are they being approved, is the corpus being read, are the hooks healthy. Distinct
from `/reflect` (which applies/dismisses individual candidates) and `/recall`
(which queries memory) — this is the audit view, like `/infra-health` for hooks
and `/stats` for cost.

## Commands

### /memory health — corpus quality rollup

```bash
python3 ~/.claude/skills/memory/scripts/memory_health.py           # text report
python3 ~/.claude/skills/memory/scripts/memory_health.py --json    # one JSON object
```

Prints a read-only report across seven sections + a one-line verdict. Never mutates
the corpus, the review queue, or the logs; degrades gracefully on every missing
source (prints "(no data yet)", never errors).

**Sections:**
- **Capture** — memory-infer hook: run count, total candidates yielded (sum of
  `appended=N` from hook detail), yield distribution (0/1/2/3+ per run).
- **Approval rate** — over resolved queue entries: `applied / (applied+dismissed)`,
  pending tracked separately. "(no resolves yet)" until the first candidate is
  applied or dismissed.
- **Invalidations** — queue `kind=invalidation` count, split stale-90d vs overlap
  (parsed from `description`).
- **Utilization** — from `memory-consulted.json`: % of corpus never consulted,
  top-5 consulted, count consulted in the last 30d. "(no data yet — read hook
  not yet active)" when the sink is absent.
- **Corpus shape** — total / no-frontmatter / flat-schema / canonical; type
  distribution; confidence distribution; `last_verified` age histogram
  (none / <30d / 30-90d / >90d); `superseded_by` count.
- **Hook health** — per memory hook: run count, error rate, mean duration.
- **Issues** — never-consulted>60d, fastest-staling (high-confidence by age, top 5),
  zero-yield infer sessions, schema-adoption %.

**Verdict** — `memory: HEALTHY` or `memory: NEEDS ATTENTION (N flags)`. Flags fire
when: any hook error rate >10%, canonical adoption <10%, or never-consulted >50%.

### /memory review — propose harness tweaks

```bash
python3 ~/.claude/skills/memory/scripts/memory_review.py
```

Reads the `/memory health` findings and proposes concrete, accept/defer harness
tweaks — each as `finding → why → action`. Advisory and deterministic: it changes
nothing. Accepting a tweak means making it a follow-up task.

Typical proposals: low schema adoption → run the S3 backfill; high never-consulted %
→ archive cruft / reseed warm-start; >25% zero-yield infer sessions → raise the
turn threshold or tighten the prompt; low approval rate → tighten the prompt; hook
error rate >10% → inspect the hook log; staling memories → re-verify via `/reflect`.

## Data sources (all read-only)

| Source | Holds |
|--------|-------|
| `~/vault/memory-review-queue.jsonl` | candidate + invalidation entries with `status` (pending/applied/dismissed) |
| `~/vault/logs/hooks.jsonl` | memory-infer / memory-validate / memory-staleness / memory-consulted hook events |
| `~/vault/logs/memory-consulted.json` | `{relpath: {count, last_seen}}` — read tracking (may not exist yet) |
| `~/.claude/projects/<project-slug>/memory/*.md` | the corpus itself (skips `MEMORY.md`, `SCHEMA.md`, `_shared.md`, dotfiles, `legacy/`) |
| `~/vault/logs/memory-staleness-state.json` | slug→date debounce map for the staleness checker |

`--json` emits one object `{capture, approval, invalidations, utilization, corpus,
hooks, issues, verdict}` for the downstream `/memory review` command.
