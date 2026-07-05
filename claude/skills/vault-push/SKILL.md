---
name: vault-push
description: "Session-end persistence. Writes a per-session handoff and updates the project's PROJECT_LOG / README / PROJECT_ARC + research links so the next /recall can resume exactly where this session left off. Use at the end of every session, or when the user says /vault push."
---

# /vault-push — Session-End Persistence

The **session-level** bookend (complement of `/recall`). Run N times a day — once at the end
of each session. Its job: persist enough that a future `/recall` resumes from exactly here.

Two modes, auto-detected by where you are.

## Detect mode & session id (run first)

```bash
# Session id: the harness sets $CLAUDE_CODE_SESSION_ID — ALWAYS prefer it. The
# cwd-match heuristic below is only a fallback: parallel sessions share a cwd, so
# "freshest marker by cwd" can resolve to a DIFFERENT live session (and clobber its
# handoff). Use the env var that names THIS session.
SID="$CLAUDE_CODE_SESSION_ID"
[ -z "$SID" ] && SID=$(ls ~/vault/logs/active-sessions/*.json 2>/dev/null | while read -r f; do
  python3 -c "import json;d=json.load(open('$f'));print(d['last_active_ts'],d['session_id'],d['cwd'])" 2>/dev/null
done | awk -v cwd="$PWD" '$3==cwd' | sort -rn | head -1 | awk '{print $2}')
[ -z "$SID" ] && SID="manual-$(date +%H%M%S)"   # last-ditch fallback if no env var + no marker
echo "session: $SID"
```

**Verify before writing:** if `$SID` came from the cwd heuristic (not the env var), sanity-check it
against THIS conversation before using it — does the marker's goal/project match what this session
actually did? A mismatched SID silently clobbers a parallel session's handoff. If it doesn't match,
use the `manual-…` fallback instead of a wrong live SID.

- **Project mode** — if `$PWD` is under `~/Documents/vault-work/Notes/<project>`, OR is a code
  repo listed in `~/Documents/vault-work/System/repo-map.yaml` (maps `~/code/<repo>` → a vault
  project). Resolve `<project>` from the path or the map. If the repo isn't mapped, ask the user
  which project it belongs to (and offer to add it to `repo-map.yaml`).
- **Default mode** — anywhere else.

---

## Mode 1: Project persistence

Write these, in order. Each is **session-scoped or project-scoped** — never a shared aggregate
(that's `/wrap-up`'s job), so parallel sessions don't clobber.

### a) Session handoff (session-scoped — always)
- Path: `Notes/.../System/handoffs/<date>/<SID>.md` → i.e.
  `~/Documents/vault-work/System/handoffs/$(date +%F)/<SID>.md`.
- `mkdir -p` the dated folder first.
- Fill from `System/templates/session-handoff.md`: frontmatter (`session_id, date, project,
  type, branch, worktree, goal, status, pr`) + body (did / decisions / state-now / open-threads
  / artifacts). Keep it tight — this is the resume point, not a transcript.

### b) PROJECT_LOG entry (project-scoped — always)
- Append to `Notes/<project>/PROJECT_LOG.md` a **sliceable** dated entry. **Header convention:
  uniform `## YYYY-MM-DD` (H2) — do NOT use `###`** (the earlier `###`-vs-`##` mix caused a
  miscount; all logs are normalized to `##`). Carry the sliceable metadata in the same heading
  line after the date:
  ```
  ## YYYY-MM-DD · <sid8> · <dev|analysis|pm> · <one-line summary>
  - what changed / decided
  - links: [[handoff]], research doc, PR
  ```
- The `## YYYY-MM-DD · …` heading format is the temporal spine `/recall` slices for
  "last week in this project" — keep it exact. `# Project Log` is the H1 title; entries are
  newest-first with **bold** sub-labels. Entry count = `grep -cE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}'`.

### c) README (project-scoped — only if state changed)
- Update `Notes/<project>/README.md` status/overview only if this session changed the project's
  current state. Don't churn it every session.

### d) PROJECT_ARC (project-scoped — only on a trajectory change)
- Update `Notes/<project>/PROJECT_ARC.md` **only** if this session moved a phase boundary, made
  a pivot, or changed the current frontier. Add a dated line under "Key pivots" / advance
  "Phases" / rewrite "Current frontier". Most sessions touch nothing here.

### e) Research links + entity linking + decisions
- If analysis produced a research doc (`Notes/<project>/research/<topic>.md`), make sure the
  handoff and PROJECT_LOG entry link it.
- **Link canonical entities:** in the handoff/log/research, link any person, metric, product, or
  tool that has a `People/` or `Glossary/` note (`[[K-factor]]`, `[[Mixpanel]]`, `[[Saurabh Jain]]`).
  If a recurring entity has no note yet, create one from `System/templates/entity.md`.
- **Decisions are vault-push-owned — capture them as ADRs.** If this session made a real decision
  (architecture, approach, scope, tool), YOU write `Notes/<project>/decisions/NNNN-<slug>.md` from
  `System/templates/decision-record.md` at session end (the L2 "why" peel) — don't leave the
  rationale only in prose, and don't defer it to `/wrap-up`. Number sequentially per project.

### f) Open Items — project-level (vault-push OWNS) + global inbox
**Project todos → `Notes/<project>/OPEN_ITEMS.md` — you own this, write it directly.** Per touched
project: **add** new todos surfaced this session, **tick done** (`- [x]`) anything resolved,
**carry** the rest. It's project-scoped (one writer) so this is parallel-safe — no inbox
indirection. Create it from `System/templates/project-open-items.md` if absent.

**Cross-cutting / ops todos (not tied to one project) → the GLOBAL ledger.** Append to the
`## Inbox (unsorted)` section at the END of `System/dashboards/Open Items.md`:
```
- <item> <!-- sid:<sid8> -->
```
You MAY tick-done a GLOBAL item this session resolved (targeted `- [x]` on that line), but do NOT
rewrite its structured tables — `/wrap-up` reconciles the global inbox into the ledger.

### f2) Resume board — `System/handoffs/RESUME.md` (L0 pointer — always, if the writer exists)

`RESUME.md` is the **L0 current-state board** — one `## <project>` section per active thread,
current-state only (the append-only history lives in each `PROJECT_LOG.md`). It's what the
warm-start hook and `/recall`'s "where were we" mode read first. Written on EVERY session end.

**Use the deterministic writer — do NOT hand-edit the file.** Section surgery on a growing board
is exactly where a clobber creeps in across parallel tabs, so this is mechanical:

```bash
python3 tools/resume_board.py update \
  --project <project> --session "<short slug>" \
  --in-flight "<mid-stream state, or 'clean stop'>" \
  --next "<next concrete step(s)>" \
  --blockers "<person/run/decision, or none>" \
  --resume-with "<literal command(s)/path(s), or 'N/A — clean stop'>"
```

The script replaces (or inserts) that project's section, moves it to the top, sets `last_touched`
+ `updated` in frontmatter, sweeps sections dormant >30d into a collapsed `## Archived` block, and
**leaves every other section byte-for-byte** — that's what keeps it clobber-safe across parallel
tabs. Multiple projects touched: run `update` once per project; run the primary one LAST so it
wins `last_touched`. Keep each section tight — it's a pointer, not the record (the "what files
changed" list belongs in the PROJECT_LOG entry). If `tools/resume_board.py` isn't present in this
vault, skip this step (the per-session handoff in step (a) is the durable fallback resume point).

### g) Commit & clean up (session-scoped — PARALLEL-SAFE)
Commit this session's work so the tree is clean — but **only this session's files**. Parallel
sessions share the repo, so **NEVER `git add -A` / `git add .`** (that sweeps a live session's
uncommitted work into your commit). The ONE sanctioned exception is `/wrap-up`'s end-of-day
commit — it's the single-writer day bookend and stages the whole vault by design; that exception
does not extend to session-level pushes. Stage explicitly:

1. **Stage** your handoff + the project files THIS session created/edited (the ones you wrote in
   steps a–f). Use exact paths, not wildcards. Include shared files (`PROJECT_LOG.md`, `Open Items.md`,
   `README`/`ARC`, `CLAUDE.md`) ONLY if `git diff` shows they contain just your additions — if a
   parallel session also edited them, stage with `git add -p` to pick only your hunks.
   - **Dependencies the script needs but git ignores** (e.g. bundled reference data under an ignored
     `data/`): `git add -f <path>` so a rebuild/clone reproduces — a "durable, not orphaned" check.
   - Verify before committing: `git diff --cached --stat` should list ONLY your files. If anything
     from another session appears, unstage it (`git restore --staged <path>`).
2. **Commit** to the vault's default branch (this repo's established pattern — every prior
   `vault-push: session …` commit is direct to main; do NOT branch for vault docs/scripts):
   ```bash
   git commit -m "vault-push: session <sid8> — <one-line summary>" -m "Co-Authored-By: Claude <noreply@anthropic.com>"
   # (use the current session's model name in the co-author if you know it, e.g. "Claude Fable 5" — don't hardcode a stale one)
   ```
3. **Push** this session's commit to the remote default branch — the session bookend persists all
   the way to origin (don't wait for `/wrap-up`). Rebase-first so a parallel session's / another
   machine's pushed commits aren't clobbered, and only YOUR commit rides up:
   ```bash
   git pull --rebase --autostash origin main && git push origin HEAD:main
   ```
   Rebase conflict (rare — two sessions touched the SAME shared file's SAME lines): resolve the
   hunk (keep BOTH sessions' additions), `git rebase --continue`, then push. If push still races
   (non-fast-forward), re-run the pull-rebase-push line. Leave other sessions' files untouched.
4. **Clean up** any scratch you created outside the vault (temp scripts in the scratchpad are fine
   to leave; don't delete other sessions' artifacts).
5. **Sweep worktrees** — if this session touched a `~/code` dev repo, sweep managed worktrees
   **after** committing/merging this session's repo work:
   ```bash
   tools/worktree.sh clean        # all enforced repos (or `clean <repo>` for one)
   ```
   **SAFE by construction:** it auto-removes a managed worktree **only** when it is clean (no
   uncommitted changes) AND fully merged into the repo's default branch — then deletes that merged
   `wt/*` branch. Anything dirty, unmerged, or hand-made is **reported, never deleted**, so its
   report doubles as a "still-open repo work" reminder — eyeball it before finishing. Never
   `rm -rf` a worktree by hand (strands git's admin refs) — use `tools/worktree.sh rm` / `clean`.
   Skip only if no `~/code` repo was touched this session (or the vault has no `tools/worktree.sh`).

### h) Mark pushed + reindex
```bash
touch ~/vault/logs/active-sessions/$SID.pushed   # clears the "unpushed" warning at next start
qmd update && qmd embed
echo '{"ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","skill":"vault-push","mode":"project","project":"<project>","sid":"'$SID'"}' >> ~/vault/logs/workflow.jsonl
```

If `qmd` is missing or errors, don't fail the push — the commit is the durable artifact; note "qmd reindex skipped" in the confirmation and move on (next `/start-work` or a manual `qmd update` catches it up).

Confirm briefly: "Pushed + committed session `<sid8>` → handoff + PROJECT_LOG (+ README/ARC if changed)."

## End Session Checklist (Mode 1)

Run through this before finishing — it's the parallel-safe superset of the old checklist,
re-pointed at the per-session/`_day.md` architecture:

```
- [ ] Session handoff written → System/handoffs/<date>/<SID>.md (step a)
- [ ] PROJECT_LOG.md entry appended per touched project — uniform `## YYYY-MM-DD · …` header (step b)
- [ ] README.md status updated if state changed (step c)
- [ ] PROJECT_ARC.md updated only on a trajectory change (step d)
- [ ] Research links wired + canonical entities linked ([[…]]) (step e)
- [ ] Decisions (if any) peeled into ADRs → Notes/<project>/decisions/NNNN-<slug>.md (step e)
- [ ] Project todos written to `Notes/<project>/OPEN_ITEMS.md` (add/tick/carry — vault-push owns it);
      cross-cutting todos appended to the GLOBAL Open Items `## Inbox (unsorted)` (step f)
- [ ] RESUME board updated — `python3 tools/resume_board.py update --project …` per touched
      project (primary last, so it wins last_touched); skip if the writer is absent (step f2)
- [ ] Git commit — explicit paths only, NEVER `git add -A`; rebase-first push to origin (step g)
- [ ] Worktrees swept — `tools/worktree.sh clean` (removes merged+clean; reports dirty/unmerged —
      eyeball it) if a ~/code repo was touched (step g)
- [ ] `touch …/$SID.pushed` + `qmd update && qmd embed` + workflow.jsonl line (step h)
```

> **Two Open-Items scopes.** vault-push **owns** each project's `Notes/<project>/OPEN_ITEMS.md`
> (writes/ticks/carries directly — parallel-safe because it's project-scoped, like PROJECT_LOG). For
> the GLOBAL `Open Items.md` it only *appends* to `## Inbox (unsorted)` (+ may tick-done a resolved
> item); the day-end `/wrap-up` is the sole writer that reconciles the global inbox into the
> structured tables and bumps its `updated:` date — that split keeps parallel sessions from
> clobbering the shared dashboard.

---

## Mode 2: Default (outside a vault project)

Lightweight daily-journal append (legacy behavior).

- Append to `~/vault/daily/YYYY-MM-DD.md` (create if missing) a `## Session — HH:MM` block:
  `### What was worked on` / `### Key decisions` / `### Open threads` (5–10 lines).
- Frontmatter `projects:` lists all projects touched that day.
- Then `touch ~/vault/logs/active-sessions/$SID.pushed` and `qmd update && qmd embed`.

### Ad-hoc note (`/vault push note <topic>`)
- Write/update `~/vault/notes/<topic-slug>.md` (frontmatter `title/created/updated/tags`); update
  `updated` on edit; one topic per note.

---

## Proactive push

At natural stopping points in a substantive session (multiple tasks done, a decision reached,
a doc produced), offer: "Want me to `/vault-push` this session before we lose the context?"
Don't push for trivial interactions.
