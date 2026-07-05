#!/usr/bin/env python3
"""Show counts of learnings by status."""

import json
import os
from collections import Counter

queue_path = os.path.expanduser("~/vault/learnings-queue.jsonl")
counts: Counter = Counter()

try:
    for line in open(queue_path):
        entry = json.loads(line)
        counts[entry.get("status", "unknown")] += 1
except FileNotFoundError:
    pass

total = sum(counts.values())
print(f"Total learnings: {total}")
for status in ["pending", "applied", "dismissed"]:
    print(f"  {status}: {counts.get(status, 0)}")
