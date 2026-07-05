#!/usr/bin/env python3
"""
Slice a Mixpanel raw-events.json into a single session and produce the
event-shape summary needed to update the knowledge base.

Usage:
  slice_session.py <raw-events.json> [--since HH:MM] [--until HH:MM] [--session-start TIMESTAMP]

Output (to stdout, JSON):
  {
    "session_start": "2026-04-13 11:20:04",
    "session_end":   "2026-04-13 11:20:26",
    "duration_s": 22,
    "event_count": 24,
    "session_start_marker": "splash_screen",   # or "home_page_v2" for app-resume
    "events": [ { "time": "HH:MM:SS", "event": "...", "params": {...only distinguishing...} }, ... ],
    "super_property_keys": [ ... ],              # filtered-out keys for reference
    "unique_events": { "event_name": count, ... },
    "personalization_context": {
       "feature_flags": { "home_referral_topnav": "lottie", "fd_home_v4": true, ... },
       "user_state":    { "current_status": "ACTIVE_BOOKING", "bonds_lifetime_status": "BOND_PURCHASED", ... },
       "cohort_props":  { "invested": true, "isSeniorCitizen": false, "user_quality_index": "P1", ... }
    },
    "catalog_deltas": {
       "dynamic_image_tapped_ids": [ {id, path, path_type, image_url, platform} ],
       "dynamic_image_viewed_ids": [ ... ],
       "dynamic_base_page_paths": [ {path, platform, type, current_page} ],
       "page_load_duration_paths": [ {path, cold_ms, warm_ms, cached} ],
       "profile_menu_items":      [ {id, path} ],
       "dashboard_nav_tabs":      [ {nav_text, index_tapped, path} ],
       "share_links":             [ "first 120 chars..." ]
    }
  }
"""
import json, sys, argparse, datetime
from collections import Counter, defaultdict

p = argparse.ArgumentParser()
p.add_argument('raw')
p.add_argument('--since', help='HH:MM — only keep events at/after this time on the same day')
p.add_argument('--until', help='HH:MM — only keep events at/before this time')
p.add_argument('--session-start', type=float, help='Force session start at this unix ts')
p.add_argument('--min-gap-min', type=int, default=30, help='Gap in minutes that signals a new session')
args = p.parse_args()

with open(args.raw) as f:
    raw = json.load(f)
events = sorted(raw['results']['events'], key=lambda e: e['properties']['time'])
if not events:
    print(json.dumps({'error': 'no events'})); sys.exit(0)

# Optional time-window filter on the same day as the latest event
day = datetime.datetime.fromtimestamp(events[-1]['properties']['time']).date()
def ts(hhmm):
    h, m = map(int, hhmm.split(':'))
    return datetime.datetime(day.year, day.month, day.day, h, m).timestamp()
if args.since:
    events = [e for e in events if e['properties']['time'] >= ts(args.since)]
if args.until:
    events = [e for e in events if e['properties']['time'] <= ts(args.until) + 59]

# Pick session start: forced > last splash_screen > first event after >N-min gap > first event
if args.session_start:
    cutoff = args.session_start
    marker = 'forced'
else:
    splashes = [e for e in events if e['event'] == 'splash_screen']
    if splashes:
        cutoff = splashes[-1]['properties']['time']
        marker = 'splash_screen'
    else:
        # find latest gap >= min_gap_min and take the event after it
        gap = args.min_gap_min * 60
        cut_idx = 0
        for i in range(len(events) - 1, 0, -1):
            if events[i]['properties']['time'] - events[i-1]['properties']['time'] >= gap:
                cut_idx = i
                break
        cutoff = events[cut_idx]['properties']['time']
        marker = 'app_resume' if cut_idx > 0 else 'session_start'

session = [e for e in events if e['properties']['time'] >= cutoff]

# Super-properties = keys present on >= 90% of events; system keys always suppressed
key_counts = Counter()
for e in session:
    for k in e['properties']:
        key_counts[k] += 1
thr = len(session) * 0.9
super_props = {k for k, c in key_counts.items() if c >= thr}
# --- Personalization context extraction ---
# Two-pronged: (1) parse the structured experimentalFeatureFlags from the
# experimental_flags / personalization_context event, (2) read known user-state
# and cohort super-properties by their exact names from the data.

# 1. Feature flags — from the `experimental_flags` or `personalization_context` event
#    These events carry an `experimentalFeatureFlags` JSON object: { flagName: {enabled, variant} }
#    They also flatten each flag as a top-level property (value = variant string or "NOT_SET").
feature_flags = {}
flag_source_event = None
for e in session:
    if e['event'] in ('experimental_flags', 'personalization_context'):
        flag_source_event = e
        break  # use the first one in the session

if flag_source_event:
    props = flag_source_event['properties']
    # Try the structured nested object first
    eff = props.get('experimentalFeatureFlags')
    if isinstance(eff, str):
        try: eff = json.loads(eff)
        except (json.JSONDecodeError, TypeError): eff = None
    if isinstance(eff, dict):
        for fname, fval in sorted(eff.items()):
            if isinstance(fval, dict):
                enabled = fval.get('enabled')
                variant = fval.get('variant')
                # Normalize: {enabled: "true", variant: "lottie"} → "lottie"
                #            {enabled: "true", variant: null}     → true
                #            {enabled: "false", ...}              → false
                if str(enabled).lower() == 'false':
                    feature_flags[fname] = False
                elif variant and str(variant).lower() not in ('null', 'none', ''):
                    feature_flags[fname] = variant
                else:
                    feature_flags[fname] = True
            else:
                feature_flags[fname] = fval
    else:
        # Fallback: read flattened top-level flag properties.
        # Feature flags are kebab-case keys with string values (variant name or "NOT_SET").
        # Exclude known non-flag keys.
        NON_FLAG_KEYS = {
            'time', 'distinct_id', 'token', 'insert_id',
            'current_status', 'life_time_status', 'status',
            'bonds_lifetime_status', 'mf_lifetime_status',
            'bonds_current_status', 'bonds_life_time_status', 'card_status',
            'invested', 'hasLifeTimeInvestment', 'isSeniorCitizen', 'isGoldMember',
            'notification_enabled', 'banksBookedIn', 'fdb_cound',
            'profileCompletionPercent', 'user_quality_index',
        }
        for k, v in sorted(props.items()):
            if k in NON_FLAG_KEYS or k.startswith('$') or k.startswith('mp_'):
                continue
            if isinstance(v, str) and v != 'NOT_SET':
                feature_flags[k] = v
            elif isinstance(v, bool):
                feature_flags[k] = v

# 2. User state — exact property names from production Mixpanel data
USER_STATE_KEYS = {
    'current_status', 'life_time_status', 'status',
    'bonds_lifetime_status', 'bonds_current_status', 'bonds_life_time_status',
    'mf_lifetime_status', 'card_status',
}

# 3. Cohort indicators — exact property names from production data
COHORT_KEYS = {
    'invested', 'hasLifeTimeInvestment', 'isSeniorCitizen', 'isGoldMember',
    'notification_enabled', 'banksBookedIn', 'fdb_cound',
    'profileCompletionPercent', 'user_quality_index',
}

# Gather modal value per super-property for state + cohort extraction
def modal_value(values_counter):
    """Return the most common raw value, coerced back from string."""
    raw = values_counter.most_common(1)[0][0]
    if raw in ('True', 'true'):  return True
    if raw in ('False', 'false'): return False
    if raw in ('None', 'null'):  return None
    try: return int(raw)
    except ValueError: pass
    try: return float(raw)
    except ValueError: pass
    return raw

super_values = defaultdict(Counter)
for e in session:
    for k in super_props:
        v = e['properties'].get(k)
        if v is not None:
            sv = json.dumps(v) if isinstance(v, (dict, list)) else str(v)
            super_values[k][sv] += 1

user_state = {}
for k in USER_STATE_KEYS:
    if k in super_values:
        user_state[k] = modal_value(super_values[k])

cohort_props = {}
for k in COHORT_KEYS:
    if k in super_values:
        cohort_props[k] = modal_value(super_values[k])

# Also check the personalization_context event's nested `props` for cohort data
if flag_source_event and flag_source_event['event'] == 'personalization_context':
    nested_props = flag_source_event['properties'].get('props')
    if isinstance(nested_props, str):
        try: nested_props = json.loads(nested_props)
        except (json.JSONDecodeError, TypeError): nested_props = None
    if isinstance(nested_props, dict):
        for k in COHORT_KEYS | USER_STATE_KEYS:
            if k in nested_props and k not in user_state and k not in cohort_props:
                if k in USER_STATE_KEYS:
                    user_state[k] = nested_props[k]
                else:
                    cohort_props[k] = nested_props[k]

personalization_context = {
    'feature_flags': feature_flags,
    'user_state': user_state,
    'cohort_props': cohort_props,
}

# always-hide system/device/mixpanel plumbing
HIDE = {'time','distinct_id','token'}
def distinguishing(e):
    out = {}
    for k, v in e['properties'].items():
        if k in super_props or k in HIDE: continue
        if k.startswith('$') or k.startswith('mp_'): continue
        if isinstance(v, (dict, list)) and len(str(v)) > 400: continue
        if isinstance(v, str) and len(v) > 400: v = v[:400] + '...'
        out[k] = v
    return out

# Catalog deltas: collect unique shapes for the umbrella events we track
def unique_by(events_list, event_name, key_fn, value_keys):
    seen = {}
    for e in events_list:
        if e['event'] != event_name: continue
        k = key_fn(e['properties'])
        if k not in seen:
            seen[k] = {key_: e['properties'].get(key_) for key_ in value_keys if key_ in e['properties']}
            seen[k][key_fn.__name__.replace('_of_', '')] = k
    return list(seen.values())

out_events = []
for e in session:
    t = datetime.datetime.fromtimestamp(e['properties']['time']).strftime('%H:%M:%S')
    out_events.append({'time': t, 'event': e['event'], 'params': distinguishing(e)})

# Umbrella catalogs
def _id(p): return p.get('id', '?')
_id.__name__ = '_of_id'
def _path(p): return p.get('path', '?')
_path.__name__ = '_of_path'

tapped_ids = unique_by(session, 'dynamic_image_tapped', _id, ['path','path_type','type','image_url','url','platform'])
viewed_ids = unique_by(session, 'dynamic_image_viewed', _id, ['path','path_type','type','image_url','platform'])
base_paths = unique_by(session, 'dynamic_base_page',    _path, ['platform','type','current_page'])

# page_load_duration: min/max load time + cache status per path
pld = defaultdict(lambda: {'cold_ms': None, 'warm_ms': None, 'cached': set()})
for e in session:
    if e['event'] != 'page_load_duration': continue
    pp = e['properties']
    path = pp.get('path', '?')
    tl = pp.get('time_to_load', 0)
    cached = pp.get('is_loaded_from_cache', None)
    pld[path]['cached'].add(cached)
    if cached is False:
        pld[path]['cold_ms'] = tl if pld[path]['cold_ms'] is None else min(pld[path]['cold_ms'], tl)
    else:
        pld[path]['warm_ms'] = tl if pld[path]['warm_ms'] is None else min(pld[path]['warm_ms'], tl)
pld_out = [{'path': k, **{kk: (list(vv) if isinstance(vv, set) else vv) for kk, vv in v.items()}} for k, v in pld.items()]

profile_items = unique_by(session, 'profile_menu_item_clicked', _id, ['path'])

nav = {}
for e in session:
    if e['event'] != 'dashboard_nav_click': continue
    pp = e['properties']
    k = (pp.get('nav_text'), pp.get('index_tapped'), pp.get('path'))
    nav[k] = {'nav_text': k[0], 'index_tapped': k[1], 'path': k[2]}

shares = []
for e in session:
    if e['event'] != 'share_app_clicked': continue
    link = e['properties'].get('link', '')
    if isinstance(link, str):
        shares.append(link[:150])

result = {
    'session_start': datetime.datetime.fromtimestamp(cutoff).strftime('%Y-%m-%d %H:%M:%S'),
    'session_end':   datetime.datetime.fromtimestamp(session[-1]['properties']['time']).strftime('%Y-%m-%d %H:%M:%S'),
    'duration_s':    int(session[-1]['properties']['time'] - cutoff),
    'event_count':   len(session),
    'session_start_marker': marker,
    'super_property_keys': sorted(super_props),
    'unique_events': dict(Counter(e['event'] for e in session)),
    'personalization_context': personalization_context,
    'catalog_deltas': {
        'dynamic_image_tapped_ids': tapped_ids,
        'dynamic_image_viewed_ids': viewed_ids,
        'dynamic_base_page_paths':  base_paths,
        'page_load_duration_paths': pld_out,
        'profile_menu_items':       profile_items,
        'dashboard_nav_tabs':       list(nav.values()),
        'share_links':              shares,
    },
    'events': out_events,
}
print(json.dumps(result, indent=2, default=str))
