# Capture Journey — Setup & Usage Guide

A tool for capturing real app sessions as structured walkthrough documents. Walk through any flow on the Stable Money app, and this skill pulls the exact Mixpanel events, correlates them with your screenshots, and produces a reusable walkthrough + event catalog update.

**Who is this for?** Anyone at Stable Money who wants to document what events fire during a specific user flow — PMs, analysts, QA, engineers.

**What you get:**
- A structured walkthrough document (markdown) mapping each screen to its events
- Raw event JSON for the session
- Updates to the shared observed-event-shapes catalog (so future queries use real event names, not guesses)

---

## First-Time Setup (do this once)

### Step 1 — Get your Mixpanel distinct_id

This is the user ID Mixpanel uses to track your events.

1. Open [Mixpanel](https://mixpanel.com) and go to the **Users** tab
2. Search for yourself by name or email
3. Click your profile
4. Copy the `distinct_id` value (looks like `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)

> Tell Claude: **"My Mixpanel distinct_id is `<paste it here>`"**
> Claude will save it so you don't have to repeat it.

### Step 2 — Get your Mixpanel session cookies

The skill uses Mixpanel's internal stream API, which requires your browser session cookies. These rotate, so you'll need to refresh them periodically.

1. Open [mixpanel.com](https://mixpanel.com) in your browser and make sure you're logged in
2. Open DevTools (`Cmd+Option+I` on Mac, `F12` on Windows)
3. Go to **Application** → **Cookies** → `https://mixpanel.com`
4. Find and copy these two values:
   - `sessionid`
   - `csrftoken`

> Tell Claude: **"My Mixpanel cookies are sessionid=`<paste>` csrftoken=`<paste>`"**
> Claude will set them as environment variables for the session.

### Step 3 — Verify it works

Claude will run a quick auth check to confirm the cookies are valid. If you see "HTTP 200" you're good. If you see 401/403, your cookies have expired — repeat Step 2.

---

## How to Capture a Journey

### 1. Walk through the flow on the app

Open Stable Money on your phone and walk through the flow you want to document. For example:
- Open the app → tap on FDs → browse rates → start a booking
- Open the app → go to referrals → share a link → check rewards

**Capture screenshots** — you have two options:

**Option A: Manual screenshots**
Take screenshots as you go — one per screen transition. Save them in a folder on your machine.

**Option B: Screen recording + auto-extract frames (recommended)**
Record your screen while walking through the flow, then extract key frames automatically:

1. Screen-record the flow on your phone (built-in screen recorder)
2. Transfer the recording to your machine
3. Go to [hintoai.com/tools/extract-frames](https://hintoai.com/tools/extract-frames)
4. Upload your screen recording
5. The tool extracts key frames (screen transitions) as individual images
6. Download the frames and save them in a folder

> This is faster and more reliable than manual screenshots — you won't miss a screen, and you can focus on the flow instead of juggling the screenshot button.

### 2. Tell Claude what you did

Say something like:

> "I just walked through the FD booking flow. Screenshots are in `~/Desktop/fd-screenshots/`. Capture the journey."

or simply:

> "Capture journey — bonds SIP setup"

Claude will ask for anything it needs:
- Your distinct_id (if not already saved)
- Fresh cookies (if expired)
- Time window (defaults to your most recent session today)
- A short name for the walkthrough (e.g. `fd-booking-2026-04-21`)

### 3. Claude does the rest

Claude will:
1. **Scrape** your Mixpanel events for the time window
2. **Slice** the session — find where your flow started, strip noise
3. **Correlate** screenshots to events by timestamp
4. **Write** a walkthrough document with:
   - What you did (narrative)
   - Screen-to-event map (table)
   - New event IDs and page paths discovered
   - Issues or missing events spotted
   - What funnels this enables
5. **Update** the shared event catalog so the whole team benefits

### 4. Review the output

Claude will show you the walkthrough. Check:
- Does the narrative match what you actually did?
- Are screenshots matched to the right events?
- Any events missing that you expected?

The walkthrough is saved at:
```
Notes/mixpanel-knowledge-base/walkthroughs/<your-slug>/
├── README.md              ← Human-readable walkthrough (for you to read)
├── instrumentation.json   ← Machine-readable event shapes (for compilation)
├── raw-events.json        ← Full event dump
├── session.json           ← Sliced + processed session
└── screenshots/           ← Your screenshots
```

Each walkthrough produces **two outputs**:
- **README.md** — human-readable walkthrough with screenshots, narrative, event map
- **instrumentation.json** — structured event shapes, property types, screen inventory, entry points — designed to be merged across flows

---

## Compiling Across Flows

This is the key step. After multiple people capture their flows, compile everything into one catalog:

> Tell Claude: **"Compile the instrumentation catalog"**

Or manually:
```bash
python3 .claude/skills/capture-journey-generic/scripts/compile_catalog.py \
  Notes/mixpanel-knowledge-base/walkthroughs/ \
  -o Notes/mixpanel-knowledge-base/compiled-catalog.json
```

The compiled catalog (`compiled-catalog.json`) contains:
- **Every event** across all flows — with property types, sample values, and which flows use it
- **Every screen** — what events fire on it, which flows visit it
- **Every entry point** — tap target IDs, destinations, which flows contain them
- **Flow index** — per-flow summary with events, screens, personalization context

This is the single source of truth for "what instrumentation exists in our app."

### Example: what the compiled catalog looks like

```json
{
  "events": {
    "dynamic_image_tapped": {
      "total_occurrences": 47,
      "seen_in_flows": ["fd-booking-new-user", "bonds-sip-setup", "referral-share"],
      "properties": {
        "id": { "types": ["string"], "sample_values": ["fd-card-123", "bonds-sip-cta"] },
        "path": { "types": ["string"], "sample_values": ["/fd-detail", "/bonds-sip"] }
      }
    }
  },
  "screens": {
    "/fd-home": {
      "platform": "DYNAMIC",
      "seen_in_flows": ["fd-booking-new-user", "fd-booking-repeat"],
      "load_events": ["dynamic_base_page", "page_load_duration"],
      "action_events": ["dynamic_image_tapped", "dynamic_image_viewed"]
    }
  }
}
```

---

## Quick Reference

| What you say | What happens |
|-------------|-------------|
| "Capture journey" | Full walkthrough flow — Claude asks what you need |
| "Scrape my events for the last 20 minutes" | Pulls events, asks if you want a full walkthrough |
| "I walked through X, add it to the catalog" | Same as capture journey, emphasizes catalog update |
| "My cookies are sessionid=... csrftoken=..." | Sets auth for the session |
| "My distinct_id is ..." | Saves your ID for future sessions |
| "Compile the instrumentation catalog" | Merges all walkthroughs into compiled-catalog.json |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "HTTP 401/403" | Cookies expired. Go to mixpanel.com, re-copy `sessionid` and `csrftoken` from DevTools |
| "0 events scraped" | Wrong distinct_id, or you used a different device. Check which device you were on |
| Events don't match my flow | Try narrowing the time window: "only events from 11:30 to 11:45" |
| "No splash_screen found" | You resumed the app instead of cold-starting. The skill handles this — it'll note "app_resume" |
| Screenshots don't line up | Clock skew between phone and Mixpanel. Events are the source of truth; screenshots are for visual context |

## Cookie Refresh Cheat Sheet

Cookies typically last a few hours. If Claude says they're expired:

1. Make sure you're logged into mixpanel.com
2. DevTools → Application → Cookies → `https://mixpanel.com`
3. Copy `sessionid` and `csrftoken`
4. Tell Claude the new values

That's it — you're back in business.

---

## For the curious: what's under the hood

```
capture-journey-generic/
├── SKILL.md                         ← Full skill instructions (Claude reads this)
├── README.md                        ← This file (human-readable guide)
├── scripts/
│   ├── scrape.sh                    ← Pulls events from Mixpanel stream API
│   ├── slice_session.py             ← Session boundaries, noise stripping, personalization extraction
│   ├── emit_instrumentation.py      ← Produces merge-friendly instrumentation.json per walkthrough
│   └── compile_catalog.py           ← Merges all instrumentation.json into one unified catalog
└── references/
    └── walkthrough-template.md      ← Template for the walkthrough document
```

**Pipeline:**
```
scrape.sh → raw-events.json
               ↓
         slice_session.py → session.json (+ personalization context)
               ↓                    ↓
    walkthrough README.md    emit_instrumentation.py → instrumentation.json
                                                              ↓
                                                   compile_catalog.py
                                                              ↓
                                                   compiled-catalog.json  ← team-wide reference
```

- **scrape.sh** hits Mixpanel's stream API with your distinct_id and date range, returns up to 1000 events as JSON
- **slice_session.py** finds your session start (last `splash_screen` or 30-min gap), filters to just that session, strips super-properties, extracts feature flags + user state + cohort props from the `experimental_flags` event, and produces catalog deltas
- **emit_instrumentation.py** transforms session.json + raw-events.json into a structured `instrumentation.json` with event shapes (property types, sample values), screen inventory, and entry points — designed for merging
- **compile_catalog.py** reads every `instrumentation.json` across all walkthroughs and merges them into a single `compiled-catalog.json` — the team-wide instrumentation reference
