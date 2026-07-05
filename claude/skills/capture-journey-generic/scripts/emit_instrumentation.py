#!/usr/bin/env python3
"""
Transform a session.json + raw-events.json into a merge-friendly
instrumentation.json that can be compiled across walkthroughs.

Usage:
  emit_instrumentation.py <session.json> <raw-events.json> \
    --slug <flow-slug> --captured-by <name> \
    > instrumentation.json

The output schema is designed so that compile_catalog.py can merge
any number of instrumentation.json files into a single unified catalog.

Schema (v1):
{
  "schema_version": 1,
  "meta": { slug, captured_by, captured_at, duration_s, event_count, session_start_marker },
  "personalization": { feature_flags, user_state, cohort_props },
  "event_sequence": [
    { seq, time_offset_s, event, params }            ← ordered, with relative timing
  ],
  "event_shapes": {
    "event_name": {
      "count": N,
      "definition": "Human-readable description of this event",
      "properties": {
        "prop_name": {
          "types": ["string"],                        ← all JSON types observed
          "sample_values": ["v1", "v2"],              ← up to 5 unique values
          "null_count": 0,
          "total_count": N
        }
      }
    }
  },
  "screens": [
    { path, platform, load_events, action_events }   ← what fires on each screen
  ],
  "entry_points": [
    { id, event, destination_path, image_url }        ← tap targets
  ]
}
"""
import json, sys, argparse, datetime, re, os
from collections import defaultdict
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('session_json')
p.add_argument('raw_events_json')
p.add_argument('--slug', required=True, help='Flow slug (e.g. fd-booking-new-user-2026-04-21)')
p.add_argument('--captured-by', required=True, help='Name of the person who walked the flow')
args = p.parse_args()

# --- Load event definitions from two sources ---
# 1. The supplement JSON (UI/platform events not in the main dictionary)
# 2. The main event-dictionary.md (parsed from markdown tables)

SCRIPT_DIR = Path(__file__).resolve().parent
SKILL_DIR = SCRIPT_DIR.parent
EVENT_DEFS = {}

# Source 1: curated supplement JSON (UI/platform events)
supplement_path = SKILL_DIR / 'references' / 'event-definitions-supplement.json'
if supplement_path.exists():
    with open(supplement_path) as f:
        supp = json.load(f)
    for k, v in supp.items():
        if not k.startswith('_'):
            EVENT_DEFS[k] = v

# Source 2: observed definitions (contributed by team during captures)
observed_path = SKILL_DIR / 'references' / 'event-definitions-observed.json'
if observed_path.exists():
    with open(observed_path) as f:
        obs = json.load(f)
    for k, v in obs.items():
        if not k.startswith('_') and isinstance(v, str):
            if k not in EVENT_DEFS:  # supplement takes priority
                EVENT_DEFS[k] = v

# Source 3: main event dictionary markdown — parse | `event_name` | description | rows
# The merged dictionary now lives in the vault's mixpanel-instrumentation skill (resolved from cwd).
dict_path = Path('.claude/skills/mixpanel-instrumentation/references/event-catalog.md')
if dict_path.exists():
    with open(dict_path) as f:
        for line in f:
            m = re.match(r'^\|\s*`([^`]+)`\s*\|\s*(.+?)\s*\|', line)
            if m:
                ename = m.group(1).strip()
                edesc = m.group(2).strip()
                if ename not in EVENT_DEFS:  # supplement + observed take priority
                    EVENT_DEFS[ename] = edesc

print(f"Loaded {len(EVENT_DEFS)} event definitions", file=sys.stderr)

with open(args.session_json) as f:
    sess = json.load(f)

with open(args.raw_events_json) as f:
    raw = json.load(f)

# --- Meta ---
meta = {
    'slug': args.slug,
    'captured_by': args.captured_by,
    'captured_at': sess['session_start'][:10],
    'duration_s': sess['duration_s'],
    'event_count': sess['event_count'],
    'session_start_marker': sess['session_start_marker'],
}

# --- Personalization ---
personalization = sess.get('personalization_context', {})

# --- Event sequence with relative timing ---
events = sess.get('events', [])
# Parse the first event's time as the baseline
def parse_hms(hms):
    parts = hms.split(':')
    return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])

baseline = parse_hms(events[0]['time']) if events else 0
event_sequence = []
for i, e in enumerate(events):
    offset = parse_hms(e['time']) - baseline
    event_sequence.append({
        'seq': i + 1,
        'time_offset_s': offset,
        'event': e['event'],
        'params': e.get('params', {}),
    })

# --- Event shapes: property type/value inventory per event ---
# Use the raw events (post-session-slice) for full property access
raw_events = sorted(raw['results']['events'], key=lambda e: e['properties']['time'])

# Filter to session window
sess_start_ts = None
sess_end_ts = None
for e in raw_events:
    t = e['properties']['time']
    ts_str = datetime.datetime.fromtimestamp(t).strftime('%Y-%m-%d %H:%M:%S')
    if ts_str == sess['session_start']:
        sess_start_ts = t
    if ts_str == sess['session_end']:
        sess_end_ts = t
# Fallback: use approximate matching
if sess_start_ts is None:
    sess_start_ts = min(e['properties']['time'] for e in raw_events)
if sess_end_ts is None:
    sess_end_ts = max(e['properties']['time'] for e in raw_events)

session_raw = [e for e in raw_events if sess_start_ts <= e['properties']['time'] <= sess_end_ts + 1]

# System/device properties to exclude from shapes
EXCLUDE_PROPS = {
    'time', 'distinct_id', 'token', 'insert_id',
    '$device_id', '$user_id', '$lib_version', '$os', '$os_version',
    '$screen_height', '$screen_width', '$screen_dpi', '$app_version_string',
    '$app_build_number', '$manufacturer', '$model', '$brand', '$carrier',
    '$wifi', '$bluetooth_enabled', '$bluetooth_version', '$has_nfc',
    '$has_telephone', '$google_play_services', '$city', '$region',
    '$country_code', '$timezone', '$locale', '$app_release',
    'mp_country_code', 'mp_lib', 'mp_processing_time_ms',
}

def json_type(v):
    if v is None: return 'null'
    if isinstance(v, bool): return 'bool'
    if isinstance(v, int): return 'int'
    if isinstance(v, float): return 'float'
    if isinstance(v, str): return 'string'
    if isinstance(v, list): return 'array'
    if isinstance(v, dict): return 'object'
    return 'unknown'

# Collect per-event property shapes
shape_data = defaultdict(lambda: {'count': 0, 'props': defaultdict(lambda: {
    'types': set(), 'samples': set(), 'null_count': 0, 'total': 0
})})

for e in session_raw:
    name = e['event']
    shape_data[name]['count'] += 1
    for k, v in e['properties'].items():
        if k in EXCLUDE_PROPS or k.startswith('$') or k.startswith('mp_'):
            continue
        pd = shape_data[name]['props'][k]
        pd['types'].add(json_type(v))
        pd['total'] += 1
        if v is None:
            pd['null_count'] += 1
        else:
            # Keep up to 5 sample values (truncate long strings)
            if len(pd['samples']) < 5:
                sv = str(v)[:200] if isinstance(v, str) else v
                if isinstance(sv, (str, int, float, bool)):
                    pd['samples'].add(str(sv))

event_shapes = {}
undefined_events = []
for ename, data in sorted(shape_data.items()):
    props = {}
    for pname, pd in sorted(data['props'].items()):
        props[pname] = {
            'types': sorted(pd['types']),
            'sample_values': sorted(pd['samples'])[:5],
            'null_count': pd['null_count'],
            'total_count': pd['total'],
        }
    shape = {
        'count': data['count'],
        'properties': props,
    }
    defn = EVENT_DEFS.get(ename)
    if defn:
        shape['definition'] = defn
    else:
        shape['definition'] = None
        undefined_events.append(ename)
    event_shapes[ename] = shape

if undefined_events:
    print(f"WARN: {len(undefined_events)} events have no definition: {', '.join(undefined_events)}", file=sys.stderr)

# --- Screens: page paths with their load + action events ---
screens = []
deltas = sess.get('catalog_deltas', {})
base_paths = deltas.get('dynamic_base_page_paths', [])
for bp in base_paths:
    path = bp.get('path', bp.get('_of_path', '?'))
    platform = bp.get('platform', 'unknown')
    # Find events that fired on this screen (matching path in params)
    load_events = set()
    action_events = set()
    for e in session_raw:
        ep = e['properties']
        if ep.get('path') == path or ep.get('current_page') == path:
            if e['event'] in ('dynamic_base_page', 'page_load_duration'):
                load_events.add(e['event'])
            elif e['event'] in ('dynamic_image_tapped', 'dynamic_image_viewed',
                                'profile_menu_item_clicked', 'dashboard_nav_click',
                                'share_app_clicked'):
                action_events.add(e['event'])
            else:
                action_events.add(e['event'])
    screens.append({
        'path': path,
        'platform': platform,
        'load_events': sorted(load_events),
        'action_events': sorted(action_events),
    })

# --- Entry points: tap targets with destinations ---
entry_points = []
tapped = deltas.get('dynamic_image_tapped_ids', [])
for t in tapped:
    entry_points.append({
        'id': t.get('id', t.get('_of_id', '?')),
        'event': 'dynamic_image_tapped',
        'destination_path': t.get('path', '?'),
        'path_type': t.get('path_type'),
        'image_url': t.get('image_url'),
        'platform': t.get('platform'),
    })

# --- Output ---
result = {
    'schema_version': 1,
    'meta': meta,
    'personalization': personalization,
    'event_sequence': event_sequence,
    'event_shapes': event_shapes,
    'screens': screens,
    'entry_points': entry_points,
}

print(json.dumps(result, indent=2, default=str))
