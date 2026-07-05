# Walkthrough — <JOURNEY NAME>

**Date:** <YYYY-MM-DD>, <HH:MM:SS>-<HH:MM:SS> IST (<DURATION>, <N> events)
**User:** <name/handle> — `distinct_id: <DISTINCT_ID>`
**Device:** <brand model>, Android/iOS <version>, app v<version>
**User state:** <current_status> / <life_time_status>, <any notable super-props — invested, bonds_purchased, senior_citizen, etc>
**Session start marker:** `splash_screen` | `app_resume` (no splash — see D6)
**Raw events:** `raw-events.json`
**Slice summary:** `session.json`

## Why this walkthrough

<One-paragraph context — what question prompted it, what product area it covers, what existing catalog gap it fills.>

## What the user did

1. <Step 1 — screen, action>
2. <Step 2 — screen, action>
3. ...

## Screen <-> Event map

| # | Time | Screenshot | Event | Key params |
|---|------|-----------|-------|-----------|
| 1 | HH:MM:SS | [[screenshots/frame-xx.png]] | `event_name` | `key=value, key2=value2` |
| 2 | HH:MM:SS | | `event_name` | `...` |

*Bold row if the event is a funnel-relevant tap / conversion moment.*

## Personalization context

What this user's session looked like — feature flags, user lifecycle state, and cohort membership. This determines what UI variant they saw.

*Auto-populated from `session.json → personalization_context`. Omit empty categories.*

### Feature flags (from `experimentalFeatureFlags`)

Extracted from the `experimental_flags` / `personalization_context` event. Each flag has a variant value (`true` = enabled with default variant, `false` = disabled, string = named variant like `"lottie"`).

| Flag | Value | Notes |
|------|-------|-------|
| `<flag_name>` | `true` / `false` / `"<variant>"` | <what it controls, if known> |

*Only list flags that are `true` or have a non-default variant — skip `false`/disabled flags unless relevant to the flow.*

### User state

| Property | Value |
|----------|-------|
| `current_status` | `<e.g. ACTIVE_BOOKING>` |
| `life_time_status` | `<e.g. BOOKING_DONE>` |
| `bonds_lifetime_status` | `<e.g. BOND_PURCHASED, NEW_USER>` |
| `mf_lifetime_status` | `<e.g. MUTUAL_FUND_PURCHASED, NOT_REGISTERED>` |
| `card_status` | `<e.g. CARD_STATUS_UNKNOWN>` |

### Cohort indicators

| Property | Value | Meaning |
|----------|-------|---------|
| `invested` | `true` / `false` | Has any FD investment |
| `hasLifeTimeInvestment` | `true` / `false` | Ever completed a transaction |
| `isSeniorCitizen` | `true` / `false` | Senior citizen flag |
| `isGoldMember` | `true` / `false` | Gold membership |
| `banksBookedIn` | `"0.0"` / `"1.0"` / `"2.0"` | Count of banks with FD bookings (string, not numeric) |
| `user_quality_index` | `P1` / `P2` / `P3` | Device/user quality tier |
| `profileCompletionPercent` | `<float>` | Profile completion (0-100) |

## Entry-point ids catalogued from this session

| Entry point | Event | `id` | Destination `path` |
|------------|-------|------|-----------------|
| <description> | `dynamic_image_tapped` | `<id>` | `<path>` |

## Pages visited

| Page `path` | What it is | Platform |
|-------------|-----------|----------|
| `<path>` | <description> | Dynamic (webview) / Flutter |

## Observations

- <Stable filter-safe ids / paths discovered>
- <How this flow differs from previously captured flows>
- <Any parameter worth knowing about>

## Issues & questions

1. <Any missing events, misnamed ids, Flutter drift, flag leaks>
2. <Questions to follow up with eng/analytics>

## Funnel implication

<What new funnel or breakdown this walkthrough enables. Include a draft filter chain using observed `id`/`path` values.>
