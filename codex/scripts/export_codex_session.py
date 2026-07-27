#!/usr/bin/env python3
"""Convert a Codex JSONL session into a vault markdown export."""
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

VAULT_SESSIONS = Path.home() / "vault" / "sessions"
NOISE_MARKERS = (
    "Use this warm-start brief as background context",
    "Warm-start brief:",
    "# Project Intelligence (auto-generated)",
    "Skill Suggestions (auto-detected)",
    "<recommended_plugins>",
    "# AGENTS.md instructions",
    "<environment_context>",
    "<permissions instructions>",
    "[external_agent_tool_call",
    "[external_agent_tool_result",
)


def slugify(text: str) -> str:
    text = text.lower().strip()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    return text[:60].strip("-") or "session"


def shorten_path(path: str, cwd: str) -> str:
    if cwd and path.startswith(cwd):
        return path[len(cwd):].lstrip("/")
    return path


def extract_text_blocks(content) -> str:
    parts: list[str] = []
    if isinstance(content, str):
        return content.strip()
    if not isinstance(content, list):
        return ""
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") in {"input_text", "output_text", "text"}:
            text = block.get("text", "").strip()
            if text:
                parts.append(text)
    return "\n\n".join(parts).strip()


def parse_jsonl(path: Path) -> dict:
    session_id = path.stem
    cwd = ""
    started_at = None
    model = ""
    cli_version = ""
    messages: list[dict] = []
    tools = Counter()
    files_touched: dict[str, set[str]] = {}

    with path.open() as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            item_type = obj.get("type")
            payload = obj.get("payload", {})
            ts = obj.get("timestamp")
            if ts and started_at is None:
                try:
                    started_at = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                except ValueError:
                    pass

            if item_type == "session_meta":
                session_id = payload.get("id", session_id)
                cwd = payload.get("cwd", cwd)
                cli_version = payload.get("cli_version", "")
                model = payload.get("model", "") or payload.get("model_provider", "")
                continue

            if item_type != "response_item":
                continue

            payload_type = payload.get("type")
            if payload_type == "message":
                role = payload.get("role", "")
                text = extract_text_blocks(payload.get("content", []))
                if role not in {"user", "assistant"}:
                    continue
                if text and not is_noise_message(text):
                    messages.append({"role": role, "text": text})
            elif payload_type == "function_call":
                tool_name = payload.get("name", "unknown")
                tools[tool_name] += 1
                raw_args = payload.get("arguments", "")
                try:
                    args = json.loads(raw_args) if isinstance(raw_args, str) and raw_args else {}
                except json.JSONDecodeError:
                    args = {}
                for key in ("path", "file_path", "workdir"):
                    value = args.get(key)
                    if isinstance(value, str) and "/" in value:
                        short = shorten_path(value, cwd)
                        files_touched.setdefault(short, set()).add(tool_name)

    if started_at is None:
        started_at = datetime.now(timezone.utc)
    date_str = started_at.strftime("%Y-%m-%d")
    first_user = title_from_messages(messages)
    project = Path(cwd).name.lower() if cwd else "general"

    return {
        "session_id": session_id,
        "date": date_str,
        "started_at": started_at,
        "cwd": cwd,
        "project": project,
        "title": first_user[:120],
        "model": model,
        "cli_version": cli_version,
        "messages": messages,
        "tools": dict(tools.most_common()),
        "files_touched": {k: sorted(v) for k, v in files_touched.items()},
        "message_count": len(messages),
    }


def is_noise_message(text: str) -> bool:
    return any(marker in text for marker in NOISE_MARKERS)


def title_from_messages(messages: list[dict]) -> str:
    for msg in messages:
        if msg["role"] != "user":
            continue
        text = msg["text"].strip()
        if not text or is_noise_message(text):
            continue
        if "A previous agent produced the plan below" in text:
            for line in text.splitlines():
                if line.startswith("# ") and not line.startswith("# AGENTS.md"):
                    return line[2:].strip()
        for line in text.splitlines():
            line = line.strip()
            if line and not line.startswith("<"):
                return line.lstrip("# ").strip()
    return "Codex session"


def render_markdown(data: dict) -> str:
    title = data["title"]
    tags = ["codex", data["project"]]
    tools = ", ".join(data["tools"].keys())
    touched_files = ", ".join(sorted(data["files_touched"]))
    lines = [
        "---",
        f'title: "{title.replace(chr(34), chr(39))}"',
        f'date: {data["date"]}',
        "source: codex",
        f'project: {data["project"]}',
        f'session_id: {data["session_id"]}',
        f'cwd: "{data["cwd"].replace(chr(34), chr(39))}"',
        f'model: "{data["model"].replace(chr(34), chr(39))}"',
        f'cli_version: "{data["cli_version"].replace(chr(34), chr(39))}"',
        f"message_count: {data['message_count']}",
        f'tools: "{tools.replace(chr(34), chr(39))}"',
        f'files_touched: "{touched_files.replace(chr(34), chr(39))}"',
        f'tags: [{", ".join(tags)}]',
        "---",
        "",
        f"# {title}",
        "",
    ]
    meta = []
    if data["model"]:
        meta.append(f'- Model: `{data["model"]}`')
    if data["cli_version"]:
        meta.append(f'- Codex CLI: `{data["cli_version"]}`')
    if data["tools"]:
        used = ", ".join(f"{name} ({count})" for name, count in data["tools"].items())
        meta.append(f"- Tools: {used}")
    if data["files_touched"]:
        touched = ", ".join(sorted(data["files_touched"]))
        meta.append(f"- Files touched: {touched}")
    if meta:
        lines.extend(["## Metadata", "", *meta, ""])

    lines.extend(["## Transcript", ""])
    for msg in data["messages"]:
        role = msg["role"].capitalize() or "Message"
        lines.append(f"### {role}")
        lines.append("")
        lines.append(msg["text"])
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: export_codex_session.py <session.jsonl> [output.md]", file=sys.stderr)
        return 1

    source = Path(sys.argv[1]).expanduser()
    if not source.exists():
        print(f"missing session file: {source}", file=sys.stderr)
        return 1

    data = parse_jsonl(source)
    slug = slugify(data["title"])
    default_name = f'{data["date"]}-{data["project"]}-{slug}.md'
    target = Path(sys.argv[2]).expanduser() if len(sys.argv) > 2 else VAULT_SESSIONS / default_name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(render_markdown(data))
    print(target)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
