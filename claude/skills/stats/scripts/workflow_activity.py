#!/usr/bin/env python3
"""Count skill invocations and verification results from workflow log."""

import json
import os
import sys
from datetime import datetime, timedelta, timezone

days = int(sys.argv[1]) if len(sys.argv) > 1 else 7
cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()

log_path = os.path.expanduser("~/vault/logs/workflow.jsonl")
skills: dict[str, int] = {}
verify_pass = 0
verify_fail = 0

try:
    for line in open(log_path):
        entry = json.loads(line)
        if entry.get("ts", "") >= cutoff:
            skill = entry.get("skill", "")
            skills[skill] = skills.get(skill, 0) + 1
            if skill == "verify-completion":
                if entry.get("result") == "pass":
                    verify_pass += 1
                elif entry.get("result") == "fail":
                    verify_fail += 1
except FileNotFoundError:
    pass

print(f"  Total invocations: {sum(skills.values())}")
for skill, count in sorted(skills.items()):
    print(f"    {skill}: {count}")
print(f"  Verifications: {verify_pass} pass / {verify_fail} fail")
