#!/usr/bin/env python3
"""Count tasks by tier from the workflow log for a given time period."""

import json
import os
import sys
from datetime import datetime, timedelta, timezone

days = int(sys.argv[1]) if len(sys.argv) > 1 else 7
cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()

log_path = os.path.expanduser("~/vault/logs/workflow.jsonl")
tiers: dict[str, int] = {}

try:
    for line in open(log_path):
        entry = json.loads(line)
        if entry.get("skill") == "task-triage" and entry.get("ts", "") >= cutoff:
            tier = entry.get("tier", "Unknown")
            tiers[tier] = tiers.get(tier, 0) + 1
except FileNotFoundError:
    pass

for tier, count in sorted(tiers.items()):
    print(f"  {tier}: {count}")
if not tiers:
    print("  No tasks logged in period")
