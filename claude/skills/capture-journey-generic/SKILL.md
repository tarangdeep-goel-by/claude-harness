---
name: capture-journey-generic
description: >
  Capture any team member's real app session, pull Mixpanel events via the stream API,
  produce a walkthrough document with screenshots, and update the observed-event-shapes
  knowledge base. Generic version — works for any user, any funnel, any product area.
  Use when anyone says "capture journey", "new walkthrough", "scrape events for <user>",
  "record the events for this flow", or provides a screenshots folder + asks to check
  recent events for a specific user.
---

# Capture Journey (Generic) — Live Event Walkthrough Skill

**Goal:** deterministically turn "someone walked through a flow on the app" into (1) a walkthrough document, (2) an update to the observed-event-shapes catalog, so future funnels can be built from real event shapes instead of guesses.

Works for any team member, any funnel, any product area.

## Canonical paths

> Reconciled to our setup: Viral's `mixpanel-analytics` skill = our **`mixpanel-instrumentation`** skill
> (the 500+ event dictionary). The observed-event-shapes catalog lives in
> `mixpanel-instrumentation/references/`. Walkthroughs live in the vault under `Notes/mixpanel-knowledge-base/`
> (auto-indexed by qmd's `projects` collection). If Viral later ships a separate `mixpanel-analytics`
> query skill, re-point these.
>
> **Copy precedence:** this is the sanitized DISTRIBUTION copy. If a vault-local `capture-journey`
> skill exists in the working vault (it does in vault-work), **that copy wins there** — it may be
> ahead of this one (e.g. its `emit_instrumentation.py` supports `--observed-defs`; this one's does
> not). Use this copy only where no vault-local variant exists.

- Walkthroughs root: `Notes/mixpanel-knowledge-base/walkthroughs/`
- Each walkthrough: `Notes/mixpanel-knowledge-base/walkthroughs/<slug>/{README.md, raw-events.json, session.json, screenshots/}`
- Catalog: `.claude/skills/mixpanel-instrumentation/references/observed-event-shapes.md`
- Vault pointer: `Notes/mixpanel-knowledge-base/README.md`
- Scripts: `.claude/skills/capture-journey-generic/scripts/{scrape.sh, slice_session.py, emit_instrumentation.py, compile_catalog.py}`
- Compiled catalog: `Notes/mixpanel-knowledge-base/compiled-catalog.json`

## Environment variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MP_SESSIONID` | Yes | — | Mixpanel web session cookie |
| `MP_CSRFTOKEN` | Yes | — | Mixpanel CSRF token cookie |
| `MP_PROJECT_ID` | No | `2879659` | Mixpanel project ID (SM default) |
| `MP_WORKSPACE_ID` | No | `3411815` | Mixpanel workspace ID (SM default) |

## Setup for new users

If this is someone's first time using capture-journey:

1. **Find their Mixpanel distinct_id:** Go to Mixpanel > Users > search by name/email > copy the `distinct_id` from their profile.
2. **Get Mixpanel cookies:** On mixpanel.com, open DevTools > Application > Cookies, copy `sessionid` and `csrftoken`.
3. **Set env vars:**
   ```bash
   export MP_SESSIONID="..."
   export MP_CSRFTOKEN="..."
   # Only needed if not using Stable Money's default project:
   # export MP_PROJECT_ID="..."
   # export MP_WORKSPACE_ID="..."
   ```

## The six steps — follow in order every time

### Step 1 — Gather inputs (use AskUserQuestion)

Collect:
- **Distinct ID** — REQUIRED, no default. Ask "whose session are we capturing?" If the user gives a name, look up their distinct_id in the vault or ask them to provide it.
- **Screenshots folder** — if the user mentioned a path, use it; otherwise skip
- **Journey slug** — short kebab-case name e.g. `fd-booking-new-user-2026-04-13`, `bonds-sip-repeat-2026-04-14`. Default = `<topic>-<YYYY-MM-DD>`
- **Time window** — default "most recent session today"; the user may say "from 11:45" or "last 20 minutes"
- **User name** — for the walkthrough metadata (who was using the app)

If multiple pieces are missing, ask ONE AskUserQuestion with all of them bundled (don't ping twice).

### Step 2 — Confirm cookies are fresh

Mixpanel session cookies rotate. Before scraping:

```bash
PROJECT_ID="${MP_PROJECT_ID:-2879659}"
WORKSPACE_ID="${MP_WORKSPACE_ID:-3411815}"

/usr/bin/curl -s -o /tmp/mp_auth_check.json -w '%{http_code}\n' \
  "https://mixpanel.com/api/query/data_definitions/events?project_id=${PROJECT_ID}&workspace_id=${WORKSPACE_ID}" \
  -H 'authorization: Session' -H "project-id: ${PROJECT_ID}" \
  -b "csrftoken=${MP_CSRFTOKEN}; sessionid=${MP_SESSIONID}"
```

If HTTP 200 -> cookies work. If 401/403 -> ask user to paste fresh `sessionid` and `csrftoken` from `mixpanel.com` browser cookies. Store them as env vars for the session.

If cookies aren't set at all at session start, tell user:
> I need fresh Mixpanel cookies. On mixpanel.com > DevTools > Application > Cookies, copy the values of `sessionid` and `csrftoken`. Paste both here.

### Step 3 — Scrape events

```bash
SLUG="<slug>"
DISTINCT_ID="<distinct_id>"
OUTDIR="Notes/mixpanel-knowledge-base/walkthroughs/${SLUG}"
mkdir -p "${OUTDIR}/screenshots"

bash .claude/skills/capture-journey-generic/scripts/scrape.sh \
  "${DISTINCT_ID}" \
  "$(date +%Y-%m-%d)" \
  "$(date +%Y-%m-%d)" \
  "${OUTDIR}/raw-events.json"
```

If the user specified a different date range, substitute it. The API returns at most 1000 events per call.

### Step 4 — Slice session + extract deltas

```bash
/usr/bin/python3 .claude/skills/capture-journey-generic/scripts/slice_session.py \
  "${OUTDIR}/raw-events.json" \
  [--since HH:MM] [--until HH:MM] \
  > "${OUTDIR}/session.json"
```

The slicer produces:
- `session_start_marker`: `splash_screen` / `app_resume` / `forced` — note if it's `app_resume` (no splash), include that in the walkthrough
- `events[]`: each event's time + name + distinguishing params (super-properties stripped automatically via 90%-threshold)
- `personalization_context`: feature flags (from `experimentalFeatureFlags` on the `experimental_flags`/`personalization_context` event), user lifecycle state (`current_status`, `bonds_lifetime_status`, etc.), and cohort indicators (`invested`, `isSeniorCitizen`, `user_quality_index`, etc.) — this tells you what UI variant the user saw and which cohorts they belong to
- `catalog_deltas`: observed `id`s, `path`s, `nav_text`s in this session — these are what get merged into the catalog

Read `session.json` to inspect. Pay special attention to `personalization_context` — it explains *why* the user saw a particular UI variant.

### Step 4b — Collect definitions for unknown events

After slicing, check which events in the session have no definition yet. Load definitions from three sources (in priority order):
1. `references/event-definitions-supplement.json` (curated UI/platform events)
2. `references/event-definitions-observed.json` (team-contributed from past captures)
3. `.claude/skills/mixpanel-instrumentation/references/event-catalog.md` (500+ events; referral entries
   are our validated ones — see `mixpanel-instrumentation/references/referral-events.md`)

For any event in `session.json` that has NO definition in any source:

1. **Show the user** the undefined events with context — event name, occurrence count, and a sample of their params from the session. This helps them recognize what the event corresponds to.

2. **Ask the user to define them.** Use AskUserQuestion or a conversational prompt like:
   > I found N events in your session that don't have definitions yet. Since you just walked through this flow, you're the best person to describe them. For each one, tell me in one sentence what it does:
   >
   > - `some_new_event` (fired 3x, params: `{type: "banner", id: "promo-123"}`) — ?
   > - `another_event` (fired 1x, params: `{screen: "checkout"}`) — ?
   >
   > You can skip any you're not sure about.

3. **Save contributed definitions** to `references/event-definitions-observed.json` using the Edit tool. Add each new definition as a key-value pair, and record the contributor in `_contributors`:

   ```json
   {
     "_contributors": {
       "some_new_event": "Alex, 2026-04-21",
       "another_event": "Priya, 2026-04-22"
     },
     "some_new_event": "Promotional banner tapped on the home screen",
     "another_event": "Checkout screen loaded"
   }
   ```

4. **If the user skips** — that's fine, the events will show up as `"definition": null` in instrumentation.json and get flagged in the compiled catalog. They can be filled in during a future capture.

This step is what makes the definitions grow organically. Each capture adds a few more. Over time, coverage approaches 100%.

### Step 5 — Copy screenshots (if provided)

Screenshots can come from two sources:
- **Manual screenshots** — user took them during the flow
- **Extracted frames from a screen recording** — user recorded the flow and extracted frames via [hintoai.com/tools/extract-frames](https://hintoai.com/tools/extract-frames)

If the user hasn't captured screenshots yet, suggest the screen-recording approach:
> **Tip:** If you have a screen recording of the flow, you can extract key frames at hintoai.com/tools/extract-frames — it's faster and you won't miss any screens.

```bash
cp "<user's folder>"/*.png "${OUTDIR}/screenshots/"
```

Read each screenshot with the Read tool and note: what screen is visible + what action appears to be in progress. Match timestamps in the image (status bar clock) to timestamps in `session.json` to correlate each screenshot to the surrounding events.

### Step 6 — Write walkthrough + update catalog

#### 6a. Write the walkthrough

Create `${OUTDIR}/README.md` using the template at `references/walkthrough-template.md`. Required sections:
- Metadata (date, duration, user, device, user state — read from the first `home_page_v2` event's super-props)
- "What the user did" — narrative from screenshots
- "Screen <-> Event map" — table time/screenshot/event/key-params
- "Observations" — stable filter-safe `id`s, page paths, share copies
- "Issues & questions" — anything surprising (missing events, misnamed ids, Flutter drift, flag leaks)
- "Funnel implication" — what filter chain this enables

#### 6b. Update the catalog — `.claude/skills/mixpanel-instrumentation/references/observed-event-shapes.md`

For each item in `session.json.catalog_deltas`:

- **New screen** (any `dynamic_base_page.path` not already in Section A) -> add a new screen subsection in Section A with load signature + actions
- **New `dynamic_image_tapped.id`** -> add a row to Section B's `dynamic_image_tapped` table
- **New `dynamic_image_viewed.id`** -> add to Section B viewed table
- **New `dynamic_base_page.path`** -> add to Section B paths table (flag `platform=PLATFORM_FLUTTER` if so)
- **New `page_load_duration.path` cold/warm time** -> update the perf table with tighter bounds
- **New `profile_menu_item_clicked.id`** -> add
- **New gotcha** (missing expected event, misnamed id, flag leak, etc.) -> add to Section D with a `D<n>` number
- **Walkthrough index** — add a row to Section E

Use the Edit tool with narrow `old_string`s (the table rows). Never rewrite the whole file.

#### 6c. Emit instrumentation.json (machine-readable, compilable)

Every walkthrough MUST produce an `instrumentation.json` alongside the human-readable README.md. This is the merge-friendly format that `compile_catalog.py` consumes.

```bash
/usr/bin/python3 .claude/skills/capture-journey-generic/scripts/emit_instrumentation.py \
  "${OUTDIR}/session.json" \
  "${OUTDIR}/raw-events.json" \
  --slug "${SLUG}" \
  --captured-by "<user name>" \
  > "${OUTDIR}/instrumentation.json"
```

The output contains:
- `event_shapes`: every event name with property types, sample values, and occurrence counts
- `event_sequence`: ordered events with relative timing (for funnel reconstruction)
- `screens`: page paths with their load and action events
- `entry_points`: tap targets with destination paths
- `personalization`: feature flags, user state, cohort props

This file is what gets compiled across all walkthroughs — do not skip it.

#### 6d. Update `Notes/mixpanel-knowledge-base/README.md` backlog

Tick off the journey if it was on the prioritised list; add a row under "Recently captured" if helpful.

## Compiling the catalog

After multiple walkthroughs have been captured (by different people, different flows), compile them into a single unified catalog:

```bash
/usr/bin/python3 .claude/skills/capture-journey-generic/scripts/compile_catalog.py \
  Notes/mixpanel-knowledge-base/walkthroughs/ \
  -o Notes/mixpanel-knowledge-base/compiled-catalog.json
```

The compiled catalog merges all `instrumentation.json` files and produces:
- **`events`**: every event name across all flows, with property shapes, sample values, and which flows use each event
- **`screens`**: every page path, what events fire on it, which flows visit it
- **`entry_points`**: every tap target ID, destination, which flows contain it
- **`flow_index`**: per-flow summary — events, screens, entry points, personalization context

Run this after each new walkthrough is captured, or periodically to refresh. The output is the team-wide instrumentation reference.

## Known team distinct_ids

Add entries here as team members use the skill:

| Name | distinct_id | Notes |
|------|-------------|-------|
| _(example)_ | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | Primary test account |
| _(example, alt)_ | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | Secondary flow-testing account |

When a user says "capture my journey" or "scrape my events," check this table first. If they're not listed, ask for their distinct_id and add them here.

## Error handling

- **Stream API returns no events:** verify the distinct_id is right; the user may have hit a different device. Try widening date range.
- **Session marker is `app_resume`:** no splash_screen in window — the user resumed the app. Note explicitly in the walkthrough.
- **Screenshot timestamps don't align** (IST vs UTC, clock skew): treat event timestamps as source of truth; screenshots are for semantic context (which screen), not for sub-second alignment.
- **Flutter page events look stripped-down:** confirm with `platform=PLATFORM_FLUTTER` in the params. If yes, catalog it as Flutter and add a gotcha if the usual events (`page_load_duration`, `share_app_clicked`) are missing.
- **Catalog edit fails** (old_string not unique): re-read the catalog, widen the context, retry.

## Environment bootstrap (first session only)

If this is the first time in a new shell and `$MP_SESSIONID` is unset:

1. Ask user for fresh cookies
2. `export MP_SESSIONID=... MP_CSRFTOKEN=...`
3. Optionally: `export MP_PROJECT_ID=... MP_WORKSPACE_ID=...` (only if not SM default)
4. Run the auth check (Step 2)

Do NOT persist cookies to disk. They rotate; always use env vars.

## When NOT to use this skill

- User is asking a question answerable from the existing catalog -> use mixpanel-instrumentation directly with `observed-event-shapes.md` already loaded.
- User wants to run a Mixpanel query (insights/funnels/flows) -> use mixpanel-instrumentation + MCP tools, not this skill.
- User wants to refactor/reorganize existing walkthroughs -> that's a vault maintenance task; don't trigger this skill.

## Quick invocation

User says **"capture journey"** / **"new walkthrough"** / **"scrape events for <name>"** / **"I walked through X, add it to the catalog"** -> follow Steps 1-6 in order.
