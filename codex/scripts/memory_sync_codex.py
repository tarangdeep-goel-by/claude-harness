#!/usr/bin/env python3
"""Sync a Codex session into Codex memories and the shared vault."""
from __future__ import annotations

import json
import os
import sys
import time
import tomllib
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

CODEX_DIR = Path.home() / ".codex"
SESSIONS_DIR = CODEX_DIR / "sessions"
MEMORY_DIR = CODEX_DIR / "memories"
VAULT_DIR = Path.home() / "vault"
DAILY_DIR = VAULT_DIR / "daily"
NOTES_DIR = VAULT_DIR / "notes"
LOG_FILE = VAULT_DIR / "logs" / "memory-sync.log"
HOOKS_LOG = VAULT_DIR / "logs" / "hooks.jsonl"
FAILURE_LOG = VAULT_DIR / "logs" / "memory-sync-failures.jsonl"
LOCK_FILE = MEMORY_DIR / ".memory-sync.lock"
MIN_MESSAGES = 6
COOLDOWN_SECS = 300
GEMINI_MODEL = "gemini-2.0-flash"
GEMINI_URL = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent"


def hook_log(outcome: str, detail: str = "", session_id: str = "", cwd: str = "") -> None:
    try:
        HOOKS_LOG.parent.mkdir(parents=True, exist_ok=True)
        entry = json.dumps(
            {
                "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "hook": "memory-sync-codex",
                "session": session_id,
                "cwd": cwd,
                "outcome": outcome,
                "detail": detail,
            }
        )
        with HOOKS_LOG.open("a") as handle:
            handle.write(entry + "\n")
    except Exception:
        pass


def log(message: str) -> None:
    print(message)
    try:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with LOG_FILE.open("a") as handle:
            handle.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}\n")
    except Exception:
        pass


def failure_log(kind: str, detail: str, session_id: str = "", cwd: str = "") -> None:
    try:
        FAILURE_LOG.parent.mkdir(parents=True, exist_ok=True)
        entry = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "hook": "memory-sync-codex",
            "kind": kind,
            "session": session_id,
            "cwd": cwd,
            "detail": detail[:1000],
        }
        with FAILURE_LOG.open("a") as handle:
            handle.write(json.dumps(entry) + "\n")
    except Exception:
        pass


def should_run() -> bool:
    if LOCK_FILE.exists():
        try:
            if time.time() - LOCK_FILE.stat().st_mtime < COOLDOWN_SECS:
                return False
        except OSError:
            pass
    return True


def touch_lock() -> None:
    MEMORY_DIR.mkdir(parents=True, exist_ok=True)
    try:
        LOCK_FILE.touch()
    except OSError:
        pass


def find_session(path_arg: str, session_id: str) -> Path | None:
    if path_arg:
        candidate = Path(path_arg).expanduser()
        if candidate.exists():
            return candidate
    if session_id:
        matches = sorted(SESSIONS_DIR.glob(f"*/*/*/{session_id}.jsonl"))
        if matches:
            return matches[-1]
    return None


def extract_text_blocks(content) -> str:
    if isinstance(content, str):
        return content.strip()
    if not isinstance(content, list):
        return ""
    parts: list[str] = []
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") in {"input_text", "output_text", "text"}:
            text = block.get("text", "").strip()
            if text:
                parts.append(text)
    return " ".join(parts).strip()


def extract_transcript(jsonl_path: Path, max_messages: int = 50):
    messages: list[str] = []
    tools_used: set[str] = set()
    files_touched: set[str] = set()
    cwd = ""
    first_ts = None

    with jsonl_path.open() as handle:
        for raw in handle:
            try:
                entry = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if not first_ts and entry.get("timestamp"):
                first_ts = entry["timestamp"]

            entry_type = entry.get("type")
            payload = entry.get("payload", {})
            if entry_type == "session_meta":
                cwd = payload.get("cwd", cwd)
                continue
            if entry_type != "response_item":
                continue

            payload_type = payload.get("type")
            if payload_type == "message":
                role = payload.get("role", "message")
                text = extract_text_blocks(payload.get("content", []))[:600]
                if text:
                    messages.append(f"[{role}]: {text}")
            elif payload_type == "function_call":
                tool_name = payload.get("name", "unknown")
                tools_used.add(tool_name)
                raw_args = payload.get("arguments", "")
                try:
                    args = json.loads(raw_args) if isinstance(raw_args, str) and raw_args else {}
                except json.JSONDecodeError:
                    args = {}
                for key in ("path", "file_path", "workdir"):
                    value = args.get(key)
                    if isinstance(value, str) and "/" in value:
                        files_touched.add(Path(value).name)

    session_date = None
    if first_ts:
        try:
            session_date = datetime.fromisoformat(first_ts.replace("Z", "+00:00")).strftime("%Y-%m-%d")
        except ValueError:
            session_date = None

    meta = []
    if tools_used:
        meta.append(f"Tools: {', '.join(sorted(tools_used)[:20])}")
    if files_touched:
        meta.append(f"Files: {', '.join(sorted(files_touched)[:20])}")
    transcript = "\n".join(meta + ["---"] + messages[-max_messages:])
    return transcript, session_date, cwd, len(messages)


def detect_project(cwd: str) -> str:
    return Path(cwd).name.lower() if cwd else "general"


def read_memories() -> dict[str, str]:
    result = {}
    if not MEMORY_DIR.exists():
        return result
    for path in sorted(MEMORY_DIR.glob("*.md")):
        if path.name.startswith("."):
            continue
        result[path.name] = path.read_text()
    return result


def read_existing_daily(today: str) -> str:
    path = DAILY_DIR / f"{today}.md"
    return path.read_text() if path.exists() else ""


def read_existing_completed(project: str) -> str:
    path = NOTES_DIR / f"{project}-completed.md"
    return path.read_text() if path.exists() else ""


def build_prompt(
    transcript: str,
    memories: dict[str, str],
    cwd: str,
    project: str,
    today: str,
    existing_daily: str,
    existing_completed: str,
) -> str:
    mem_text = "\n\n".join(f"### {name}\n```\n{content}\n```" for name, content in memories.items())
    return f"""You are a session analysis system for a developer knowledge base. Analyze this Codex session and produce THREE outputs in a single JSON response.

## Session Info
- Working directory: {cwd}
- Project: {project}
- Date: {today}

## Current Memory Files
{mem_text}

## Existing Daily Entry for {today}
```
{existing_daily or '(none yet)'}
```

## Existing Completed Notes for {project}
```
{existing_completed[-2000:] if existing_completed else '(none yet)'}
```

## Session Transcript
{transcript}

## Output Format
Respond with a JSON object containing three keys:

{{
  "memory_updates": [
    {{"action": "update|create", "filename": "...", "content": "...", "reason": "..."}},
    {{"action": "skip", "reason": "..."}}
  ],
  "daily_entry": {{
    "should_append": true/false,
    "content": "markdown to APPEND to daily file (not the full file)"
  }},
  "completed_entry": {{
    "should_append": true/false,
    "content": "markdown to APPEND to completed notes (not the full file)"
  }}
}}

## Rules
1. Only update memory files when the session contains new, durable information.
2. Trivial sessions should usually return no memory updates and no append operations.
3. Avoid duplicates if the same work is already captured.
4. For daily entries, append a short session note with What was worked on, Key decisions, and Open threads.
5. For completed notes, include only meaningful completed work and mention key files when relevant.

Respond with ONLY valid JSON. No markdown fences."""


def call_gemini(prompt: str, api_key: str) -> str | None:
    data = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": 0.1,
            "maxOutputTokens": 4096,
            "responseMimeType": "application/json",
        },
    }
    req = urllib.request.Request(
        f"{GEMINI_URL}?key={api_key}",
        data=json.dumps(data).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            return result["candidates"][0]["content"]["parts"][0]["text"]
    except (urllib.error.URLError, KeyError, IndexError, json.JSONDecodeError) as exc:
        log(f"Codex sync: Gemini call failed - {exc}")
        return None


def parse_response(text: str | None):
    if not text:
        return None
    text = text.strip()
    if text.startswith("```"):
        text = "\n".join(line for line in text.splitlines() if not line.startswith("```")).strip()
    try:
        data = json.loads(text)
        return data if isinstance(data, dict) else None
    except json.JSONDecodeError:
        pass
    start = text.find("{")
    end = text.rfind("}")
    if start >= 0 and end > start:
        try:
            data = json.loads(text[start : end + 1])
            return data if isinstance(data, dict) else None
        except json.JSONDecodeError:
            return None
    return None


def apply_memory_updates(updates) -> int:
    MEMORY_DIR.mkdir(parents=True, exist_ok=True)
    count = 0
    for op in updates or []:
        if op.get("action") == "skip":
            continue
        filename = op.get("filename", "")
        content = op.get("content", "")
        if not filename.endswith(".md") or "/" in filename or ".." in filename or not content:
            continue
        path = MEMORY_DIR / filename
        if path.exists() and path.read_text().strip() == content.strip():
            continue
        path.write_text(content)
        count += 1
    return count


def apply_daily_entry(daily_data, today: str, project: str) -> bool:
    if not daily_data or not daily_data.get("should_append"):
        return False
    content = daily_data.get("content", "").strip()
    if not content:
        return False
    DAILY_DIR.mkdir(parents=True, exist_ok=True)
    path = DAILY_DIR / f"{today}.md"
    if path.exists():
        existing = path.read_text()
        first_line = content.splitlines()[0].strip()
        if first_line and first_line in existing:
            return False
        with path.open("a") as handle:
            handle.write(f"\n{content}\n")
    else:
        header = f"---\ndate: {today}\nprojects: [{project}]\n---\n\n# {today}\n\n{content}\n"
        path.write_text(header)
    return True


def apply_completed_entry(completed_data, project: str) -> bool:
    if not completed_data or not completed_data.get("should_append"):
        return False
    content = completed_data.get("content", "").strip()
    if not content:
        return False
    NOTES_DIR.mkdir(parents=True, exist_ok=True)
    path = NOTES_DIR / f"{project}-completed.md"
    if path.exists():
        existing = path.read_text()
        first_line = content.splitlines()[0].strip()
        if first_line and first_line in existing:
            return False
        with path.open("a") as handle:
            handle.write(f"\n{content}\n")
    else:
        path.write_text(f"Folder Context: Permanent knowledge notes, project docs, research.\n---\n\n{content}\n")
    return True


def load_api_key() -> str:
    for env_name in ("GOOGLE_API_KEY", "GEMINI_API_KEY"):
        if os.environ.get(env_name):
            return os.environ[env_name]
    config_path = CODEX_DIR / "config.toml"
    if config_path.exists():
        with config_path.open("rb") as handle:
            data = tomllib.load(handle)
        mcp_servers = data.get("mcp_servers", {})
        for server_name in ("gemini_bridge", "gemini-bridge"):
            api_key = mcp_servers.get(server_name, {}).get("env", {}).get("GEMINI_API_KEY", "")
            if api_key:
                return api_key
    return ""


def main() -> int:
    try:
        input_data = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        input_data = {}

    session_id = input_data.get("session_id", "")
    session_path = input_data.get("session_path", "")
    jsonl_path = find_session(session_path, session_id)
    if not jsonl_path:
        log("Codex sync: no transcript found, skipping")
        hook_log("skip", "no transcript", session_id, input_data.get("cwd", ""))
        return 0

    api_key = load_api_key()
    if not api_key:
        log("Codex sync: no Gemini API key, skipping")
        hook_log("skip", "no api key", session_id, input_data.get("cwd", ""))
        return 0

    if not should_run():
        log("Codex sync: cooldown active, skipping")
        hook_log("skip", "cooldown", session_id, input_data.get("cwd", ""))
        return 0

    transcript, session_date, cwd, message_count = extract_transcript(jsonl_path)
    if message_count < MIN_MESSAGES:
        log(f"Codex sync: too short ({message_count} messages), skipping")
        hook_log("skip", f"too short ({message_count} messages)", session_id, cwd)
        return 0

    today = session_date or datetime.now(timezone.utc).strftime("%Y-%m-%d")
    project = detect_project(cwd)
    memories = read_memories()
    prompt = build_prompt(
        transcript,
        memories,
        cwd,
        project,
        today,
        read_existing_daily(today),
        read_existing_completed(project),
    )

    touch_lock()
    response = call_gemini(prompt, api_key)
    if response is None:
        failure_log("model", "Gemini call returned no response", session_id, cwd)
        hook_log("error", "model call failed", session_id, cwd)
        return 0
    result = parse_response(response)
    if not result:
        log("Codex sync: failed to parse Gemini response")
        failure_log("parse", response[:1000], session_id, cwd)
        hook_log("error", "invalid model response", session_id, cwd)
        return 0

    mem_count = apply_memory_updates(result.get("memory_updates", []))
    daily_ok = apply_daily_entry(result.get("daily_entry", {}), today, project)
    completed_ok = apply_completed_entry(result.get("completed_entry", {}), project)
    hook_log("ok", f"memory={mem_count} daily={int(daily_ok)} completed={int(completed_ok)}", session_id, cwd)
    log(f"Codex sync: memory={mem_count} daily={daily_ok} completed={completed_ok}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
