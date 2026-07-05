# evals — does the harness actually work?

Two complementary gates. Both stand up a **fresh adopter install in a throwaway `HOME`** so nothing
touches your real setup.

| Eval | Question | Auth/cost | Where |
|---|---|---|---|
| `../tests/clean-room.sh` | Are the right files/symlinks/config produced by install + update? Does a seeded session get exported/indexed? Does bootstrap/daily-jobs run? (**structural + pipeline**) | none | **CI** (`.github/workflows/clean-room.yml`, ubuntu + macOS) + local |
| `../tests/hooks-smoke.sh` | Does every hook survive a representative event, and do the safety hooks actually block/allow? (**behavioral, no LLM**) | none | **CI** + local |
| `qmd-recall.sh` | Does the search spine index + recall end-to-end (BM25 + semantic)? | none (needs qmd installed) | **local** (CI has no qmd; models ~2GB) |
| `agent-clean-room.sh` | Can a real **agent** DO the expected things on a fresh install? (**behavioral**) | Claude auth + ~tokens | **maintainer-local** (CI can't auth) |

## Structural gate (CI)
Runs on every push/PR. A broken `install.sh`/`update.sh` can't merge. Run locally too:
```bash
bash tests/clean-room.sh
```

## Search-spine eval (local, no auth)
CI can't run this — qmd isn't installed there and its models are ~2GB. Run locally on a machine
with qmd to prove `/recall` actually works end-to-end (seeds a doc in a throwaway project-local
index → embeds → asserts both `qmd search` and `qmd query` surface it; sanity-checks the global
`index.yml`):
```bash
bash evals/qmd-recall.sh
```

## Agent behavioral eval (maintainer-run)
Drives headless `claude -p` through capability cases and asserts on **side effects** (hook fired,
file written, tooling ran) — not brittle text matching. Reads auth from the environment; **no token
is stored in the repo**:
```bash
export ANTHROPIC_BASE_URL=https://api.anthropic.com
export ANTHROPIC_AUTH_TOKEN=sk-ant-...        # billed pay-as-you-go at API rates
./evals/agent-clean-room.sh                    # optional: EVAL_MODEL=claude-sonnet-... for deeper cases
```
It prints the total `total_cost_usd` for the run.

**Cost:** ~**\$0.25–0.75** per full run on Haiku (7 cases, incl. the heavier `/vault-push` +
`/wrap-up`; the default model — cases test the harness, not model smarts). Higher on Sonnet/Opus.
`run_agent` retries once on a transient 429, so back-to-back runs don't flake on throttling.

**Cases today** (each a distinct promised capability):
1. **context injection** — warm-start fires on the agent's session and the agent reads the injected brief.
2. **tooling** — the agent finds and runs harness tooling (the telemetry collector).
3. **vault write** — the agent writes a note into the correct vault structure.
4. **`/start-work`** — runs the day engine; writes the day-started marker.
5. **`/vault-push`** — persists a handoff (project mode) or the daily journal (default mode).
6. **`/recall`** — surfaces a seeded session (reuses the real qmd models via a symlink, fresh index; skipped if qmd/models absent).
7. **`/wrap-up`** — rolls the day's session handoffs into `_day.md`.

**Add a case:** append a `run_agent "<task>"` + a side-effect `chk` in `agent-clean-room.sh`. Prefer
asserting a file/log side effect over matching agent prose.

> Why the agent eval isn't in CI: it needs Claude auth and spends tokens. Run it before a release or
> after a change that touches the agent-facing surface (skills, warm-start, settings, CLAUDE.md).
