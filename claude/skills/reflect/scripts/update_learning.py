#!/usr/bin/env python3
"""Update a learning's status in the learnings queue."""

import json
import os
import sys
from datetime import datetime, timezone


def update_learning(trigger_text: str, new_status: str, applied_to: str | None = None):
    queue_path = os.path.expanduser("~/vault/learnings-queue.jsonl")
    if not os.path.exists(queue_path):
        print(f"Queue file not found: {queue_path}", file=sys.stderr)
        sys.exit(1)

    lines = open(queue_path).readlines()
    updated = False
    with open(queue_path, "w") as f:
        for line in lines:
            entry = json.loads(line)
            if (
                entry.get("trigger_text") == trigger_text
                and entry.get("status") == "pending"
                and not updated
            ):
                entry["status"] = new_status
                if applied_to:
                    entry["applied_to"] = applied_to
                entry[f"{new_status}_at"] = datetime.now(timezone.utc).strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                )
                updated = True
            f.write(json.dumps(entry) + "\n")

    if updated:
        print(f"Learning updated to '{new_status}'")
    else:
        print("No matching pending learning found", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(
            "Usage: update_learning.py <trigger_text> <status> [applied_to]",
            file=sys.stderr,
        )
        sys.exit(1)

    trigger = sys.argv[1]
    status = sys.argv[2]
    target = sys.argv[3] if len(sys.argv) > 3 else None
    update_learning(trigger, status, target)
