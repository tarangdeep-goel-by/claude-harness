---
name: analysis
description: "Run a product/data analysis on the sm-analytics backbone (Mixpanel / Metabase / PostHog / MoEngage / AppsFlyer), build funnels, persist the script, and write findings to a research doc. Use for: \"analyze\", \"build a funnel\", \"pull metrics\", \"what's the conversion\", \"investigate <metric>\", \"cohort analysis\". Enforces the lib-first rule."
---

# /analysis — Analysis on the sm-analytics Backbone

Our analytics backbone is `~/code/sm-analytics` — it already covers a lot of ground. Every
analysis (a) imports the lib (never re-implements SQL/API/business logic), (b) persists its
script, and (c) writes findings to a research doc the next `/recall` can find.

## Cardinal rule — lib-first
- SQL / API calls / business-number logic live in `~/code/sm-analytics` (SHA-pinned). Scripts
  only **import and orchestrate**. New reusable logic → add a method to the lib, don't inline it.
- Run scripts with the lib venv: `~/code/sm-analytics/.venv/bin/python`.

## Behavioral contract
- **Explainer, not calculator.** Report only numbers a script produced THIS session; anything else
  is "not computed" + an offered follow-up pull. Never interpolate.
- **Check the premise before explaining it.** "Why did X drop?" → first verify X is real (event
  coverage erosion, per-bucket summing vs cross-window unique, identity gaps, lagging tables).
  Most historical "drops" were instrumentation artifacts; only explain confirmed movements.
- **Ballpark first.** State the expected magnitude + its benchmark before the pull; a result >2×
  off gets investigated, not reported.
- **Scope fence.** Deliver the asked cut; further cuts are OFFERS at the end. Done = script
  persisted + research doc updated + every number citing `<script> @ <date>`.
- **Subagent briefs decay.** Copy the skill-specific invariants (lib-first, API caps/units,
  persist + sanity-block) VERBATIM into every subagent prompt — the vault's `mixpanel-analytics`
  and `metabase-query` skills carry ready-made paste blocks for this.

## What the lib gives you (in `sm_analytics/`)
- **clients/**: `MetabaseClient`, `MixpanelClient` (hot session + cold JQL), `PostHogClient`
  (creds gap: `POSTHOG_*` may be unset — see [[project-posthog-migration]]), `MoEngageClient`
  (self-refreshing auth, see [[reference-sm-analytics-clients]]), `AppsFlyerClient`,
  `ControlHubClient`, `Gupshup*`, `SheetsClient`/`DriveClient` (SA key `~/.claude/.gsheets-sa.json`),
  `GenericCache` (SQLite base).
- **funnels/**: `funnels/referral.py` → `referral_funnel()` + `ReferralFunnelResult` /
  `FunnelMetrics`, event/LP-path constants (`*_SHARE_EVENT`, `*_REFERRAL_LP_PATHS`,
  `REFERRAL_SHARE_IDS`). **Reuse these for referral funnels — don't rebuild the stages.**
- **cohorts/**: `ReferralCache` over `~/.cache/referral_cost_v4/canonical.db`.

## Steps

### 1. Catch up (don't recompute / contradict)
- `recall topic <area>` and `recall context <project>`.
- Read the project's `methodology.md` (the number contract) and prior `research/` docs. For
  referral work, [[reference-referral-methodology]] is mandatory.

### 2. Scaffold the script
- Create `~/code/<repo>/scripts/<name>.py` (or `Notes/<project>/scripts/` for vault-local
  one-offs) importing the right client(s) / `referral_funnel()`.
- Parameterize date window + cohort/segment ids. Add `--limit` / `--dry-run` for fast tests.

### 3. Run
- Short jobs inline.
- **Long jobs as tracked background jobs with a real logfile** — NOT `nohup` under a subagent
  (stdout pipe closes and it hangs; known failure, see [[reference-sm-analytics-clients]]).
  Use the Bash tool's `run_in_background` with output to a logfile, or `run_daily.sh`-style
  logging to `~/.cache/...`. Validate fixes with a targeted probe before a full multi-hour scrape.

### 4. Persist findings → research doc
- Write `Notes/<project>/research/<topic>.md` from `System/templates/research-doc.md`:
  Question / Method (lib methods + window + ids + script path) / Findings (numbers first) /
  Caveats / Links. Cite the script path so the analysis is reproducible.
- Cross-link methodology + related research + any decision it informs.

### 5. Hand off
- End the session with `/vault-push` (project mode): it links the research doc from
  `PROJECT_LOG`, and updates `PROJECT_ARC` if the finding shifts the project's direction.
- If you added/changed lib logic, that's a code change → use `/dev-task` to PR it into
  `sm-analytics` (and bump consumers' pins).

## Notes
- The Referee Quality Tracker pipeline lives in the vault: `Notes/referral-program/scripts/`
  (+ `README.md` / `REBUILD_SPEC.md`); the daily cache-pull→compute→publish runs as the
  `aop-tracker-daily` job in `daily-jobs.yaml` (via `/start-work`). Use `/analysis` for
  general/new analyses; edit those scripts directly to change the tracker.
- Gotchas live in memory: Mixpanel JQL 60/hr cap, MoEngage classified-403 on sensitive cohorts,
  `get_cohort_count` broken. Check [[reference-sm-analytics-clients]] before deep work.
