#!/usr/bin/env python3
"""
Compile all instrumentation.json files across walkthroughs into a single
unified instrumentation catalog.

Usage:
  compile_catalog.py <walkthroughs_root> [-o compiled-catalog.json]

Example:
  compile_catalog.py Notes/mixpanel-knowledge-base/walkthroughs/ \
    -o Notes/mixpanel-knowledge-base/compiled-catalog.json

Reads every <slug>/instrumentation.json under the walkthroughs root.
Merges into:

{
  "schema_version": 1,
  "compiled_at": "2026-04-21",
  "source_count": 12,
  "sources": [ { slug, captured_by, captured_at, event_count, duration_s } ],

  "events": {
    "event_name": {
      "total_occurrences": N,
      "seen_in_flows": ["slug1", "slug2"],
      "properties": {
        "prop_name": {
          "types": ["string", "int"],
          "sample_values": ["v1", "v2", "v3"],
          "seen_in_flows": ["slug1"]
        }
      }
    }
  },

  "screens": {
    "/path": {
      "platform": "DYNAMIC",
      "seen_in_flows": ["slug1"],
      "load_events": ["dynamic_base_page"],
      "action_events": ["dynamic_image_tapped"]
    }
  },

  "entry_points": {
    "id_value": {
      "event": "dynamic_image_tapped",
      "destination_path": "/fd-detail",
      "seen_in_flows": ["slug1"],
      "path_type": "...",
      "platform": "..."
    }
  },

  "flow_index": {
    "slug1": {
      "event_names": ["splash_screen", "home_page_v2", ...],
      "screen_paths": ["/fd-home", ...],
      "entry_point_ids": ["fd-card-123", ...],
      "personalization": { feature_flags, user_state, cohort_props }
    }
  }
}
"""
import json, sys, argparse, os, datetime
from collections import defaultdict
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('walkthroughs_root', help='Root folder containing walkthrough subdirectories')
p.add_argument('-o', '--output', help='Output path (default: stdout)')
args = p.parse_args()

root = Path(args.walkthroughs_root)
if not root.is_dir():
    print(f"ERROR: {root} is not a directory", file=sys.stderr)
    sys.exit(1)

# Discover all instrumentation.json files
inst_files = sorted(root.glob('*/instrumentation.json'))
if not inst_files:
    print(f"No instrumentation.json files found under {root}", file=sys.stderr)
    sys.exit(1)

print(f"Found {len(inst_files)} instrumentation files", file=sys.stderr)

# Accumulators
sources = []
events = defaultdict(lambda: {
    'total_occurrences': 0,
    'definition': None,
    'seen_in_flows': [],
    'properties': defaultdict(lambda: {
        'types': set(),
        'sample_values': set(),
        'seen_in_flows': [],
    })
})
screens = defaultdict(lambda: {
    'platform': None,
    'seen_in_flows': [],
    'load_events': set(),
    'action_events': set(),
})
entry_points = defaultdict(lambda: {
    'event': None,
    'destination_path': None,
    'seen_in_flows': [],
    'path_type': None,
    'platform': None,
})
flow_index = {}

for fpath in inst_files:
    with open(fpath) as f:
        try:
            inst = json.load(f)
        except json.JSONDecodeError as e:
            print(f"WARN: skipping {fpath} — invalid JSON: {e}", file=sys.stderr)
            continue

    if inst.get('schema_version') != 1:
        print(f"WARN: skipping {fpath} — unknown schema_version", file=sys.stderr)
        continue

    meta = inst['meta']
    slug = meta['slug']
    sources.append({
        'slug': slug,
        'captured_by': meta.get('captured_by'),
        'captured_at': meta.get('captured_at'),
        'event_count': meta.get('event_count'),
        'duration_s': meta.get('duration_s'),
    })

    # Merge event shapes
    for ename, edata in inst.get('event_shapes', {}).items():
        ev = events[ename]
        ev['total_occurrences'] += edata.get('count', 0)
        ev['seen_in_flows'].append(slug)
        # Keep the first non-null definition encountered
        if ev['definition'] is None and edata.get('definition'):
            ev['definition'] = edata['definition']
        for pname, pdata in edata.get('properties', {}).items():
            prop = ev['properties'][pname]
            prop['types'].update(pdata.get('types', []))
            for sv in pdata.get('sample_values', []):
                if len(prop['sample_values']) < 10:
                    prop['sample_values'].add(sv)
            if slug not in prop['seen_in_flows']:
                prop['seen_in_flows'].append(slug)

    # Merge screens
    for scr in inst.get('screens', []):
        path = scr.get('path', '?')
        s = screens[path]
        s['platform'] = s['platform'] or scr.get('platform')
        s['seen_in_flows'].append(slug)
        s['load_events'].update(scr.get('load_events', []))
        s['action_events'].update(scr.get('action_events', []))

    # Merge entry points
    for ep in inst.get('entry_points', []):
        epid = ep.get('id', '?')
        e = entry_points[epid]
        e['event'] = e['event'] or ep.get('event')
        e['destination_path'] = e['destination_path'] or ep.get('destination_path')
        e['path_type'] = e['path_type'] or ep.get('path_type')
        e['platform'] = e['platform'] or ep.get('platform')
        if slug not in e['seen_in_flows']:
            e['seen_in_flows'].append(slug)

    # Flow index
    flow_index[slug] = {
        'event_names': sorted(inst.get('event_shapes', {}).keys()),
        'screen_paths': [s.get('path', '?') for s in inst.get('screens', [])],
        'entry_point_ids': [ep.get('id', '?') for ep in inst.get('entry_points', [])],
        'personalization': inst.get('personalization', {}),
    }

# Serialize sets to sorted lists
def clean(obj):
    if isinstance(obj, set):
        return sorted(str(x) for x in obj)
    if isinstance(obj, defaultdict):
        return {k: clean(v) for k, v in obj.items()}
    if isinstance(obj, dict):
        return {k: clean(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [clean(x) for x in obj]
    return obj

# Collect events that still have no definition
undefined = sorted(ename for ename, edata in events.items() if edata['definition'] is None)
if undefined:
    print(f"WARN: {len(undefined)} events have no definition: {', '.join(undefined[:20])}", file=sys.stderr)

result = {
    'schema_version': 1,
    'compiled_at': datetime.date.today().isoformat(),
    'source_count': len(sources),
    'sources': sources,
    'events': clean(events),
    'screens': clean(screens),
    'entry_points': clean(entry_points),
    'flow_index': flow_index,
    'undefined_events': undefined,
}

output = json.dumps(result, indent=2, default=str)
if args.output:
    with open(args.output, 'w') as f:
        f.write(output)
    print(f"Compiled catalog → {args.output} ({len(sources)} flows, {len(events)} events, {len(screens)} screens)", file=sys.stderr)
else:
    print(output)
