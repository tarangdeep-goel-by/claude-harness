#!/bin/bash
# UserPromptSubmit hook: detect which vault skill a prompt needs and inject a
# reminder to LOAD that skill BEFORE answering. The skills carry the durable
# truth (event dictionaries, table/column names, playbooks, API patterns);
# guessing = silently-wrong data or rework. Observe-only: always allows the
# prompt (exit 0); only adds context.
#
# Built because custom skills were under-invoked (129 sessions: mixpanel-analytics
# 3x, metabase-query 1x, play-console 2x, capture-journey 0, flutter-dev 0).
# Generalizes the earlier data-skill-router (mixpanel+metabase) to all the
# routing-sensitive skills. The CLAUDE.md routing rules stand regardless.
set -uo pipefail

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | python3 -c "import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
print((d.get('prompt') or '').lower())" 2>/dev/null || true)
CWD=$(echo "$INPUT" | python3 -c "import sys,json
try: print(json.load(sys.stdin).get('cwd',''))
except Exception: pass" 2>/dev/null || true)

case "$CWD" in *vault-work*) ;; *) exit 0 ;; esac
[ -z "$PROMPT" ] && exit 0
# Skip meta-discussion ABOUT skills/infra (talking about, not doing the work)
if echo "$PROMPT" | grep -qiE 'skill|hook|route|routing|invoke|trigger'; then exit 0; fi

LINES=""
add() { LINES="$LINES
- $1"; }
m() { echo "$PROMPT" | grep -qiE "$1"; }

m 'mixpanel|funnel|cohort|retention|\bdau\b|\bmau\b|segmentation|payment success|fds? booked|bonds? payment|mf orders?|onboarding (funnel|drop|flow)|drop.?off|conversion rate|event name|\bsm_[a-z]|\btd_[a-z]|\bsb_[a-z]|dynamic_image_tapped|dynamic_base_page|how many .*(booked|paid|issued|users)|unique users|\btraffic\b' \
  && add "mixpanel-analytics — any event/funnel/cohort/metric. Read SKILL.md + references/ (event-dictionary, programmatic-api); never guess an event name (wrong variant = silently wrong data)."

m 'build (a )?(chart|funnel|report|dashboard)|add to (the |my )?(mixpanel )?(dashboard|board)|create a funnel in mixpanel|save (this )?(as )?(a )?report|update (my |the )?(mixpanel )?board|commit (the |a )?chart|mixpanel report' \
  && add "mixpanel-chart-builder — building/committing a Mixpanel report. Follow spec→validate (observed-event-shapes)→preview→commit. If an event/id isn't observed yet, capture-journey first."

m 'metabase|\bsql\b|which table|table for|\bschema\b|\bdb ?2[0-9]\b|\bdb ?3[0-9]\b|user_referee|user_reward_transaction|user_fixed_deposit|run (this )?query|pull (the )?data|export .*(data|csv)|reward total|\baum\b|transaction (count|table|level)' \
  && add "metabase-query — any table/schema/SQL. Confirm table + columns from the skill; never guess."

m 'play console|play store|app store|store listing|custom listing|product page|\bcvr\b|acquisition|\baso\b|app reviews?|\bratings\b|\bppo\b|utm source|search quer|a/b.*(listing|store|ppo)' \
  && add "play-console — Play Console / App Store analytics (listings, CVR, acquisition, A/B/PPO, reviews). Use the skill's API patterns."

m 'flutter|stable_money_flutter|stable-flutter|build (a |the )?(widget|screen|page|bottom.?sheet)|implement (this|the) (design|screen|figma)|wire up the .* (component|widget|page)' \
  && add "flutter-dev — Flutter widget/screen build. MANDATORY: read the skill + Urvesh's playbook (≤10 files/PR, no API/nav/DS edits, trSafe + camelCase keys, branch from dev) BEFORE writing code."

m 'capture journey|new walkthrough|scrape (my |the )?events|scrape events for|record (the )?events|capture .*(session|journey)|screenshots folder|check .*recent events' \
  && add "capture-journey — capturing a real app session into the event catalogue. Follow the skill (stream API + walkthrough + update observed-event-shapes)."

m 'transcribe|meeting notes from|process (this|the) (transcript|call|recording)|here.?s (the |what ).*(transcript|discussed)|summari[sz]e the call|raw transcript' \
  && add "transcriber — meeting transcript/recording → structured note. Use transcribe.sh + the transcriber flow (don't hand-summarize)."

m 'did .* refer|why .*(no|did ?n.?t).*(reward|referral)|referral for \+?[0-9]|investigate referral|cx .*(referral|reward)|control ?hub.*referral|clicked .*link.*nothing|referral (case|escalation)|why .*did ?n.?t .* get .* reward' \
  && add "referral-investigation — CX referral forensics (phone-pair reconciliation across Mixpanel + Metabase DB29). Run the skill's L1/L2 script; don't eyeball a verdict."

[ -z "$LINES" ] && exit 0

MSG="SKILL ROUTING — load the skill(s) BEFORE answering (durable truth lives there; guessing = wrong data / rework). Applies even to a quick ask:${LINES}
(CLAUDE.md routing rules.)"
python3 -c "import json,sys; print(json.dumps({'hookSpecificOutput':{'hookEventName':'UserPromptSubmit','additionalContext':sys.argv[1]}}))" "$MSG" 2>/dev/null || true
exit 0
