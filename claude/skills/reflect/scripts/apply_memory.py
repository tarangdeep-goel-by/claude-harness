#!/usr/bin/env python3
"""Apply or dismiss a memory candidate from ~/vault/memory-review-queue.jsonl.

Used by the `/reflect memory` subcommand. The N argument is the 1-based index
into the pending candidates sorted by confidence (high > medium > low), matching
the table that `/reflect memory` displays — so the index the user picks always
refers to the same ordering this script uses.

apply_memory.py <queue_path> <N> apply   [--memory-dir <dir>]
apply_memory.py <queue_path> <N> dismiss

On apply:
  - Writes <memory-dir>/<name>.md with canonical frontmatter.
  - Appends one line to <memory-dir>/MEMORY.md.
  - Flips that queue entry's status to "applied".
On dismiss:
  - Flips that queue entry's status to "dismissed".

Default memory dir is the canonical Projects-umbrella memory location on this
harness. Never exits non-zero on the happy path; surfaces errors to stderr but
the caller (a Claude slash command) is not blocked.
"""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone

DEFAULT_MEMORY_DIR = os.path.expanduser(
    "~/.claude/projects/-Users-tarang-Documents-Projects/memory"
)

# confidence rank for sorting (lower sorts first = displayed first)
CONF_RANK = {"high": 0, "medium": 1, "low": 2}


def _today() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def _read_queue(path: str) -> list[dict]:
    entries: list[dict] = []
    if not os.path.exists(path):
        return entries
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except Exception:
                continue
    return entries


def _write_queue(path: str, entries: list[dict]) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        for e in entries:
            f.write(json.dumps(e) + "\n")
    os.replace(tmp, path)


def _pending_sorted(entries: list[dict]) -> list[tuple[int, dict]]:
    """Return list of (original_index, entry) for pending entries, sorted by
    confidence (high>medium>low) then by name for stable display."""
    pending = [
        (i, e)
        for i, e in enumerate(entries)
        if e.get("status") == "pending" and e.get("kind") == "memory_candidate"
    ]
    pending.sort(
        key=lambda ie: (
            CONF_RANK.get(str(ie[1].get("confidence", "low")).lower(), 9),
            str(ie[1].get("name", "")),
        )
    )
    return pending


def _slugify(s: str) -> str:
    out = []
    for ch in s.strip().lower():
        if ch.isalnum():
            out.append(ch)
        elif ch in ("-", "_", " "):
            out.append("-")
    slug = "".join(out)
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug.strip("-")


def apply_one(
    queue_path: str, n: int, memory_dir: str
) -> tuple[bool, str]:
    entries = _read_queue(queue_path)
    pending = _pending_sorted(entries)
    if n < 1 or n > len(pending):
        return False, f"index {n} out of range (pending={len(pending)})"
    orig_idx, entry = pending[n - 1]

    name = _slugify(entry.get("name") or "")
    if not name:
        return False, "candidate has no usable name"
    desc = str(entry.get("description", "")).strip()
    body = str(entry.get("body", "")).strip()
    ctype = str(entry.get("type", "user")).strip() or "user"
    conf = str(entry.get("confidence", "low")).strip().lower() or "low"

    os.makedirs(memory_dir, exist_ok=True)
    mem_path = os.path.join(memory_dir, f"{name}.md")
    today = _today()
    frontmatter = (
        "---\n"
        f"name: {name}\n"
        f"description: {desc}\n"
        "metadata:\n"
        f"  type: {ctype}\n"
        f"  confidence: {conf}\n"
        f"  created: {today}\n"
        f"  last_verified: {today}\n"
        "---\n"
    )
    # Don't clobber an existing memory file of the same name — abort cleanly.
    if os.path.exists(mem_path):
        return False, f"memory file already exists: {mem_path}"
    with open(mem_path, "w") as f:
        f.write(frontmatter + "\n" + body + "\n")

    # Append to MEMORY.md (create if missing).
    memory_md = os.path.join(memory_dir, "MEMORY.md")
    line = f"- [{name}]({name}.md) — {desc}\n"
    if os.path.exists(memory_md):
        with open(memory_md, "a") as f:
            f.write(line)
    else:
        with open(memory_md, "w") as f:
            f.write(line)

    # Flip queue status.
    entry["status"] = "applied"
    entry["applied_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    entry["applied_to"] = mem_path
    entries[orig_idx] = entry
    _write_queue(queue_path, entries)
    return True, f"applied #{n} → {mem_path} (+ MEMORY.md line)"


def dismiss_one(queue_path: str, n: int) -> tuple[bool, str]:
    entries = _read_queue(queue_path)
    pending = _pending_sorted(entries)
    if n < 1 or n > len(pending):
        return False, f"index {n} out of range (pending={len(pending)})"
    orig_idx, entry = pending[n - 1]
    entry["status"] = "dismissed"
    entry["dismissed_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    entries[orig_idx] = entry
    _write_queue(queue_path, entries)
    return True, f"dismissed #{n}"


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print(
            "usage: apply_memory.py <queue_path> <N> apply|dismiss [--memory-dir <dir>]",
            file=sys.stderr,
        )
        return 2
    queue_path = argv[1]
    try:
        n = int(argv[2])
    except ValueError:
        print(f"error: N must be an integer, got {argv[2]!r}", file=sys.stderr)
        return 2
    action = argv[3]
    memory_dir = DEFAULT_MEMORY_DIR
    if "--memory-dir" in argv:
        i = argv.index("--memory-dir")
        if i + 1 < len(argv):
            memory_dir = os.path.expanduser(argv[i + 1])

    if action == "apply":
        ok, msg = apply_one(queue_path, n, memory_dir)
        print(msg)
        return 0 if ok else 1
    elif action == "dismiss":
        ok, msg = dismiss_one(queue_path, n)
        print(msg)
        return 0 if ok else 1
    else:
        print(f"error: unknown action {action!r}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
