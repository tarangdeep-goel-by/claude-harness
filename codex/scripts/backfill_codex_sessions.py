#!/usr/bin/env python3
"""Backfill meaningful Codex JSONL sessions into the shared vault markdown archive."""
from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

SESSIONS = Path.home() / ".codex" / "sessions"
VAULT = Path.home() / "vault" / "sessions"
EXPORTER = Path.home() / ".codex" / "scripts" / "export_codex_session.py"


def load_exporter():
    spec = importlib.util.spec_from_file_location("export_codex_session", EXPORTER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load exporter: {EXPORTER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def already_exported(session_id: str) -> bool:
    for path in VAULT.glob("*.md"):
        try:
            head = path.read_text(errors="ignore")[:1200]
        except OSError:
            continue
        if f"session_id: {session_id}" in head or f'session_id: "{session_id}"' in head:
            return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--min-messages", type=int, default=6)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    exporter = load_exporter()
    candidates = []
    for path in sorted(SESSIONS.glob("*/*/*/*.jsonl"), key=lambda p: p.stat().st_mtime):
        data = exporter.parse_jsonl(path)
        if data["message_count"] < args.min_messages:
            continue
        if already_exported(data["session_id"]):
            continue
        candidates.append((path, data))
        if args.limit and len(candidates) >= args.limit:
            break

    if args.dry_run:
        print(f"would_export={len(candidates)}")
        for path, data in candidates[:20]:
            print(f"{data['date']} {data['session_id']} messages={data['message_count']} {path}")
        return 0

    VAULT.mkdir(parents=True, exist_ok=True)
    exported = 0
    for path, data in candidates:
        slug = exporter.slugify(data["title"])
        target = VAULT / f"{data['date']}-{data['project']}-codex-{data['session_id']}-{slug}.md"
        target.write_text(exporter.render_markdown(data))
        exported += 1
    print(f"exported={exported}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
