#!/usr/bin/env python3
"""Native Codex hook adapter for the shared harness scripts."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

HOME = Path.home()
WARM_START = HOME / ".codex" / "scripts" / "codex_warm_start.sh"
VAULT_SCRIPTS = HOME / "vault" / "scripts"
HOOKS_LOG = HOME / "vault" / "logs" / "hooks.jsonl"
STOP_WORKER = HOME / ".codex" / "scripts" / "codex_stop_worker.sh"
EXPORT_SCRIPT = HOME / ".codex" / "scripts" / "export_codex_session.py"
QMD_REFRESH = HOME / ".codex" / "scripts" / "codex_qmd_refresh.sh"
CODE_GRAPH_CACHE = HOME / ".codex" / "plugins" / "cache" / "code-graph-mcp" / "code-graph-mcp"

MAX_SESSION_WORDS = 1200
MAX_SESSION_WORDS_ABSOLUTE = 1500
MAX_PROMPT_WORDS = 400
MAX_PROMPT_BULLETS = 4

SENSITIVE_BASENAMES = {
    ".env",
    ".env.local",
    ".env.production",
    ".env.staging",
    ".env.development",
    "id_rsa",
    "id_ed25519",
    "id_ecdsa",
    "id_dsa",
    "credentials.json",
    "credentials.yaml",
    "credentials.yml",
    ".netrc",
    ".npmrc",
    "secrets.yaml",
    "secrets.yml",
    "secrets.json",
}
SENSITIVE_EXTENSIONS = (".pem", ".key", ".p12", ".pfx", ".jks", ".keystore")
SENSITIVE_DIR_PARTS = (
    "/.ssh/",
    "/.gnupg/",
    "/.config/gcloud/",
    "/.kube/config",
    "/.docker/config.json",
    "/.aws/credentials",
    "/.aws/config",
)


def read_input() -> dict[str, Any]:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return {"_raw": raw}
    return data if isinstance(data, dict) else {}


def emit(obj: dict[str, Any]) -> int:
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    return 0


def log_hook(event: str, outcome: str, detail: str = "", data: dict[str, Any] | None = None) -> None:
    try:
        HOOKS_LOG.parent.mkdir(parents=True, exist_ok=True)
        entry = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "hook": f"codex-{event}",
            "outcome": outcome,
            "detail": detail[:500],
        }
        if data:
            session = str(data.get("session_id") or data.get("turn_id") or "")
            cwd = str(data.get("cwd") or data.get("working_directory") or "")
            if session:
                entry["session"] = session
            if cwd:
                entry["cwd"] = cwd
        with HOOKS_LOG.open("a") as handle:
            handle.write(json.dumps(entry) + "\n")
    except Exception:
        pass


def word_cap(text: str, max_words: int, absolute: int | None = None) -> str:
    words = text.split()
    limit = min(max_words, absolute) if absolute is not None else max_words
    if len(words) <= limit:
        return text.strip()
    return " ".join(words[:limit]).strip() + "\n\n[truncated by Codex hook adapter]"


def compact_bullets(text: str) -> str:
    lines = [line.rstrip() for line in text.splitlines()]
    bullets = [line for line in lines if line.lstrip().startswith("- ")]
    if bullets:
        header = next((line for line in lines if line.startswith("## ")), "## Skill Suggestions")
        text = "\n".join([header, *bullets[:MAX_PROMPT_BULLETS]])
    return word_cap(text, MAX_PROMPT_WORDS)


def run_script(path: Path, payload: dict[str, Any], timeout: int) -> subprocess.CompletedProcess[str] | None:
    if not path.exists():
        return None
    return run_command([str(path)], payload, timeout)


def run_command(argv: list[str], payload: dict[str, Any], timeout: int) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(
            argv,
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return subprocess.CompletedProcess(argv, 124, "", str(exc))


def blocking_reason(proc: subprocess.CompletedProcess[str] | None) -> str:
    if proc is None:
        return ""
    if proc.returncode == 2:
        return (proc.stderr or proc.stdout or "hook blocked").strip()
    if not proc.stdout.strip():
        return ""
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return ""
    decision = str(data.get("decision") or data.get("permissionDecision") or "").lower()
    if decision in {"deny", "block"}:
        return str(data.get("reason") or data.get("message") or "hook blocked")
    return ""


def run_observe(event: str, detail: str, proc: subprocess.CompletedProcess[str] | None, payload: dict[str, Any]) -> None:
    if proc is None:
        log_hook(event, "skip", f"{detail} missing", payload)
    elif proc.returncode not in {0, 124}:
        log_hook(event, "warn", f"{detail}: {(proc.stderr or proc.stdout).strip()}", payload)


def code_graph_scripts_dir() -> Path | None:
    if not CODE_GRAPH_CACHE.exists():
        return None
    candidates = sorted(
        (path / "scripts" for path in CODE_GRAPH_CACHE.iterdir() if path.is_dir()),
        key=lambda path: path.parent.name,
        reverse=True,
    )
    for scripts in candidates:
        if scripts.exists():
            return scripts
    return None


def run_node_hook(script_name: str, payload: dict[str, Any], timeout: int) -> subprocess.CompletedProcess[str] | None:
    scripts = code_graph_scripts_dir()
    if scripts is None:
        return None
    script = scripts / script_name
    if not script.exists():
        return None
    return run_command(["node", str(script)], payload, timeout)


def first_dict(data: dict[str, Any], keys: tuple[str, ...]) -> dict[str, Any]:
    for key in keys:
        value = data.get(key)
        if isinstance(value, dict):
            return value
    return {}


def first_str(data: dict[str, Any], keys: tuple[str, ...]) -> str:
    for key in keys:
        value = data.get(key)
        if isinstance(value, str) and value:
            return value
    return ""


def parse_args(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    if isinstance(value, str) and value.strip():
        try:
            parsed = json.loads(value)
            return parsed if isinstance(parsed, dict) else {}
        except json.JSONDecodeError:
            return {}
    return {}


def normalize_tool(data: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    nested = first_dict(data, ("tool_call", "toolCall", "call", "invocation", "request"))
    tool_name = (
        first_str(data, ("tool_name", "tool", "name", "toolName"))
        or first_str(nested, ("tool_name", "tool", "name", "toolName"))
    )
    tool_input = first_dict(data, ("tool_input", "toolInput", "input", "arguments", "args"))
    if not tool_input:
        tool_input = first_dict(nested, ("tool_input", "toolInput", "input", "arguments", "args"))
    if not tool_input:
        tool_input = parse_args(data.get("arguments") or nested.get("arguments"))

    command = first_str(tool_input, ("command", "cmd", "shell_command", "shellCommand"))
    if not command:
        command = first_str(data, ("command", "cmd"))
    if command:
        tool_input = {**tool_input, "command": command}
        if not tool_name or tool_name.lower() in {"shell", "exec", "exec_command", "unified_exec", "shell_command"}:
            tool_name = "Bash"

    lowered = tool_name.lower()
    if lowered in {"read", "fs_read", "fs_read_file"}:
        tool_name = "Read"
    elif lowered in {"write", "fs_write", "fs_write_file"}:
        tool_name = "Write"
    elif lowered in {"edit", "apply_patch"}:
        tool_name = "Edit"
    elif lowered in {"bash", "shell", "exec_command", "unified_exec", "shell_command"}:
        tool_name = "Bash"
    return tool_name or "", tool_input


def normalize_payload(data: dict[str, Any]) -> dict[str, Any]:
    tool_name, tool_input = normalize_tool(data)
    cwd = first_str(data, ("cwd", "working_directory", "workingDirectory", "project_dir", "projectDir"))
    prompt = first_str(data, ("prompt", "user_prompt", "userPrompt", "input_text", "inputText"))
    if not prompt:
        user_input = data.get("user_input") or data.get("userInput")
        if isinstance(user_input, str):
            prompt = user_input
        elif isinstance(user_input, dict):
            prompt = first_str(user_input, ("text", "prompt"))
    return {
        **data,
        "cwd": cwd,
        "source": first_str(data, ("source", "hook_source")) or "codex",
        "prompt": prompt,
        "tool_name": tool_name,
        "tool_input": tool_input,
        "input": tool_input,
    }


def codex_source(source: str) -> str:
    if source in {"startup", "clear"}:
        return f"codex-{source}"
    return source or "codex"


def session_start(data: dict[str, Any]) -> int:
    payload = normalize_payload(data)
    warm_payload = {
        "session_id": payload.get("session_id") or payload.get("turn_id") or "codex",
        "source": codex_source(str(payload.get("source") or "startup")),
        "cwd": payload.get("cwd") or os.getcwd(),
    }
    run_observe("session-start", "session-marker", run_command([str(VAULT_SCRIPTS / "session-marker-hook.sh"), "start"], warm_payload, timeout=3), payload)
    proc = run_script(WARM_START, warm_payload, timeout=10)
    if proc is None:
        log_hook("session-start", "skip", "warm-start missing", payload)
        return 0
    if proc.returncode != 0 and not proc.stdout.strip():
        log_hook("session-start", "error", proc.stderr.strip(), payload)
        return 0
    context = proc.stdout.strip()
    try:
        parsed = json.loads(context)
        context = (
            parsed.get("hookSpecificOutput", {}).get("additionalContext")
            or parsed.get("additionalContext")
            or context
        )
    except json.JSONDecodeError:
        pass
    run_observe("session-start", "persist-env", run_script(VAULT_SCRIPTS / "persist-env-hook.sh", warm_payload, timeout=5), payload)
    run_observe("session-start", "memory-staleness", run_script(VAULT_SCRIPTS / "memory-staleness-check.sh", warm_payload, timeout=5), payload)
    context = word_cap(str(context), MAX_SESSION_WORDS, MAX_SESSION_WORDS_ABSOLUTE)
    log_hook("session-start", "ok", f"{len(context.split())} words", payload)
    return emit({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": context}})


def user_prompt_submit(data: dict[str, Any]) -> int:
    payload = normalize_payload(data)
    prompt = payload.get("prompt", "")
    if not prompt or str(prompt).startswith("/"):
        return 0
    proc = run_script(VAULT_SCRIPTS / "skill-retrieval-hook.sh", payload, timeout=8)
    if proc is None or not proc.stdout.strip():
        return 0
    try:
        parsed = json.loads(proc.stdout)
        context = parsed.get("hookSpecificOutput", {}).get("additionalContext") or parsed.get("additionalContext", "")
    except json.JSONDecodeError:
        context = proc.stdout
    context = compact_bullets(str(context))
    if not context:
        return 0
    log_hook("user-prompt-submit", "ok", f"{len(context.split())} words", payload)
    return emit({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": context}})


def sensitive_path_reason(path_text: str) -> str:
    if not path_text:
        return ""
    expanded = str(Path(path_text.replace("~", str(HOME), 1)))
    basename = Path(expanded).name
    if basename in SENSITIVE_BASENAMES:
        return f"sensitive file: {basename}"
    if basename.startswith("service-account") and basename.endswith(".json"):
        return f"service account key: {basename}"
    if basename.endswith(SENSITIVE_EXTENSIONS):
        return f"key/certificate file: {basename}"
    for part in SENSITIVE_DIR_PARTS:
        if part in expanded:
            return f"sensitive path: {part.strip('/')}"
    return ""


def bash_secret_read_reason(command: str) -> str:
    if not command:
        return ""
    reader = r"(^|[ \t])(cat|less|more|head|tail|sed|awk|grep|rg|bat|nl|python3?|ruby|node)[ \t]"
    secret = r"(\.env([A-Za-z0-9_.-]*)?|id_(rsa|ed25519|ecdsa|dsa)|\.ssh/|\.gnupg/|\.aws/(credentials|config)|\.docker/config\.json|\.kube/config|service-account[^ \t]*\.json)"
    if re.search(reader, command) and re.search(secret, command):
        return "command appears to read sensitive files"
    return ""


def dangerous_command_reason(command: str) -> str:
    checks = (
        (r"\brm\s+(-[A-Za-z]*r[A-Za-z]*f|--recursive)\s+(/|~/|\.|\.\.|\*|['\"]\.['\"])", "rm -rf targets a broad path"),
        (r"\bgit\s+push\s+.*(-f|--force)(\s|$)", "git force push can overwrite remote history"),
        (r"\bgit\s+reset\s+--hard\b", "git reset --hard discards uncommitted changes"),
        (r"\bgit\s+(checkout|restore)\s+\.\s*$", "git checkout/restore . discards unstaged changes"),
        (r"\bgit\s+clean\s+-[A-Za-z]*f\b", "git clean -f permanently deletes untracked files"),
        (r"\bgit\s+branch\s+-D\s+", "git branch -D can lose unmerged work"),
        (r"\bdocker\s+system\s+prune\b", "docker system prune removes broad Docker state"),
        (r"\bchmod\s+(-R\s+)?777\b", "chmod 777 creates world-writable permissions"),
        (r"\b(DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s+TABLE|DELETE\s+FROM\s+\w+\s*;)", "destructive SQL detected"),
    )
    for pattern, reason in checks:
        if re.search(pattern, command, flags=re.IGNORECASE):
            return reason
    return ""


def block(reason: str, event: str, data: dict[str, Any]) -> int:
    log_hook(event, "block", reason, data)
    return emit({"decision": "block", "reason": reason})


def pre_tool_use(data: dict[str, Any]) -> int:
    payload = normalize_payload(data)
    tool_name = payload.get("tool_name", "")
    tool_input = payload.get("tool_input", {})
    command = str(tool_input.get("command") or "")

    pre_hooks: list[tuple[str, subprocess.CompletedProcess[str] | None]] = []
    if tool_name in {"Write", "Edit", "MultiEdit", "NotebookEdit"}:
        pre_hooks.append(("workflow-gate", run_script(VAULT_SCRIPTS / "workflow-gate-hook.sh", payload, timeout=3)))
    if tool_name in {"Read", "Write", "Edit", "Bash"}:
        pre_hooks.append(("file-guard", run_script(VAULT_SCRIPTS / "file-guard-hook.sh", payload, timeout=3)))
    if tool_name == "Bash":
        pre_hooks.append(("block-dangerous", run_script(VAULT_SCRIPTS / "block-dangerous-hook.sh", payload, timeout=3)))
        pre_hooks.append(("code-graph-pre-grep", run_node_hook("pre-grep-guide.js", payload, timeout=3)))
    if tool_name in {"Read"}:
        pre_hooks.append(("code-graph-pre-read", run_node_hook("pre-read-guide.js", payload, timeout=3)))
    if tool_name in {"Write", "Edit", "MultiEdit", "NotebookEdit"}:
        pre_hooks.append(("worktree-guard", run_script(VAULT_SCRIPTS / "worktree-guard-hook.sh", payload, timeout=3)))
        pre_hooks.append(("code-graph-pre-edit", run_node_hook("pre-edit-guide.js", payload, timeout=3)))

    for name, proc in pre_hooks:
        reason = blocking_reason(proc)
        if reason:
            return block(f"{name}: {reason}", "pre-tool-use", payload)
        run_observe("pre-tool-use", name, proc, payload)

    if tool_name in {"Read", "Write", "Edit"}:
        path_text = str(tool_input.get("file_path") or tool_input.get("path") or "")
        reason = sensitive_path_reason(path_text)
        if reason:
            return block(f"File Guard: blocked access to {reason}", "pre-tool-use", payload)
    if tool_name == "Bash":
        reason = bash_secret_read_reason(command) or dangerous_command_reason(command)
        if reason:
            return block(f"Command Guard: {reason}", "pre-tool-use", payload)
    return 0


def permission_request(data: dict[str, Any]) -> int:
    payload = normalize_payload(data)
    tool_name = str(payload.get("tool_name") or "")
    command = str(payload.get("tool_input", {}).get("command") or "")
    safe_tools = {"Read", "Glob", "Grep", "Search", "ListFiles", "list_files", "search", "read"}
    if tool_name in safe_tools:
        log_hook("permission-request", "allow", tool_name, payload)
        return emit({"decision": "allow"})
    python_pattern = r"(^|[|;&]\s*)(uv\s+run\s+)?python3?\s+(- <<|-c|-m py_compile|-m pytest|\S+\.py\b)"
    if tool_name == "Bash" and re.search(python_pattern, command):
        if not dangerous_command_reason(command) and not bash_secret_read_reason(command):
            log_hook("permission-request", "allow", "python exploration", payload)
            return emit({"decision": "allow"})
    return 0


def post_tool_use(data: dict[str, Any]) -> int:
    payload = normalize_payload(data)
    tool_name = payload.get("tool_name")
    hooks: list[tuple[str, subprocess.CompletedProcess[str] | None]] = []
    if tool_name in {"Write", "Edit", "MultiEdit", "NotebookEdit"}:
        hooks.append(("auto-test", run_script(VAULT_SCRIPTS / "auto-test-hook.sh", payload, timeout=5)))
        hooks.append(("memory-validate", run_script(VAULT_SCRIPTS / "memory-validate-hook.sh", payload, timeout=5)))
    if tool_name in {"Skill", "Task"}:
        hooks.append(("tool-telemetry", run_script(VAULT_SCRIPTS / "tool-telemetry-hook.sh", payload, timeout=3)))
    if tool_name == "Read":
        hooks.append(("memory-consulted", run_script(VAULT_SCRIPTS / "memory-consulted-hook.sh", payload, timeout=3)))
    if tool_name == "Bash":
        hooks.append(("code-graph-post-grep", run_node_hook("post-grep-inject.js", payload, timeout=5)))
    for name, proc in hooks:
        run_observe("post-tool-use", name, proc, payload)
        if proc and proc.stdout.strip() and name == "code-graph-post-grep":
            sys.stdout.write(proc.stdout if proc.stdout.endswith("\n") else proc.stdout + "\n")
    return 0


def latest_session() -> str:
    paths = sorted((HOME / ".codex" / "sessions").glob("*/*/*/*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    return str(paths[0]) if paths else ""


def text_from_content(content: Any) -> str:
    if isinstance(content, str):
        return content.strip()
    if not isinstance(content, list):
        return ""
    parts = []
    for block in content:
        if isinstance(block, dict) and block.get("type") in {"input_text", "output_text", "text"}:
            text = str(block.get("text") or "").strip()
            if text:
                parts.append(text)
    return "\n\n".join(parts).strip()


def snapshot_noise(text: str) -> bool:
    markers = (
        "This session is being continued",
        "Base directory for this skill",
        "<recommended_plugins>",
        "# AGENTS.md instructions",
        "<environment_context>",
        "<permissions instructions>",
        "tool_result",
        "[external_agent_tool_call",
        "[external_agent_tool_result",
    )
    return not text or text.startswith("<") or any(marker in text for marker in markers)


def short_line(text: str, limit: int = 200) -> str:
    text = " ".join(text.split())
    return text[:limit] + ("..." if len(text) > limit else "")


def git_output(cwd: str, args: list[str]) -> str:
    if not cwd:
        return ""
    try:
        proc = subprocess.run(
            ["git", "-C", cwd, *args],
            text=True,
            capture_output=True,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return proc.stdout.strip() if proc.returncode == 0 else ""


def parse_session_state(session_path: Path) -> tuple[str, str, list[str]]:
    session_id = session_path.stem
    cwd = ""
    prompts: list[str] = []
    try:
        with session_path.open() as handle:
            for line in handle:
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                payload = row.get("payload") if isinstance(row.get("payload"), dict) else {}
                if row.get("type") == "session_meta":
                    session_id = str(payload.get("id") or session_id)
                    cwd = str(payload.get("cwd") or cwd)
                    continue
                if row.get("type") != "response_item" or payload.get("type") != "message":
                    continue
                if payload.get("role") != "user":
                    continue
                text = text_from_content(payload.get("content", []))
                if not snapshot_noise(text):
                    prompts.append(text)
    except OSError:
        pass
    return session_id, cwd, prompts[-3:]


def write_precompact_snapshot(session_path: str, payload: dict[str, Any], transcript_path: str) -> str:
    source = Path(session_path)
    parsed_session_id, parsed_cwd, prompts = parse_session_state(source)
    session_id = str(payload.get("session_id") or parsed_session_id or source.stem)
    cwd = str(payload.get("cwd") or parsed_cwd or os.getcwd())
    project = Path(cwd).name or "unknown"
    branch = git_output(cwd, ["rev-parse", "--abbrev-ref", "HEAD"])
    last_commit = git_output(cwd, ["log", "-1", "--oneline"])
    status = [line for line in git_output(cwd, ["status", "--short"]).splitlines() if line.strip()][:15]
    compacted_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    date = time.strftime("%Y-%m-%d")
    hhmmss = time.strftime("%H%M%S")
    sid8 = (session_id or "unknown")[:8]

    lines = [
        "---",
        f"session_id: {session_id}",
        f"compacted_at: {compacted_at}",
        f"project: {project}",
        f'cwd: "{cwd.replace(chr(34), chr(39))}"',
    ]
    if branch:
        lines.append(f"branch: {branch}")
    if last_commit:
        lines.append(f'last_commit: "{last_commit.replace(chr(34), chr(39))}"')
    if transcript_path:
        lines.append(f'transcript: "{transcript_path.replace(chr(34), chr(39))}"')
    lines.extend(["source: codex", "type: precompact-state", "---", "", f"# Pre-compact state snapshot - {project}", ""])
    lines.extend([
        "Auto-written by the Codex PreCompact hook (deterministic; no model call).",
        "Captures the environment state the transcript export omits: git working tree and active goal.",
        "",
        "## Active goal (recent user prompts)",
    ])
    if prompts:
        lines.extend(f"- {short_line(prompt)}" for prompt in prompts)
    else:
        lines.append("- (no user prompts recovered)")
    lines.extend(["", "## Git state"])
    if branch:
        lines.append(f"- branch: `{branch}`")
        lines.append(f"- last commit: {last_commit}")
        if status:
            lines.append("- working tree:")
            lines.extend(f"  - `{item}`" for item in status)
        else:
            lines.append("- working tree: clean")
    else:
        lines.append("- (not a git repo or git unavailable)")
    lines.extend(["", "## Resume", f"- Full transcript: {transcript_path or '(not exported)'}", f"- cwd: `{cwd}`", ""])

    target_dir = HOME / "vault" / "sessions"
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / f"{date}_precompact_{sid8}_{hhmmss}.md"
    target.write_text("\n".join(lines))
    return str(target)


def pre_compact(data: dict[str, Any]) -> int:
    payload = normalize_payload(data)
    session_path = str(payload.get("transcript_path") or payload.get("session_path") or payload.get("sessionPath") or latest_session())
    if not session_path or not Path(session_path).exists():
        log_hook("pre-compact", "skip", "no session file", payload)
        return 0
    transcript_path = ""
    if EXPORT_SCRIPT.exists():
        try:
            proc = subprocess.run(
                ["python3", str(EXPORT_SCRIPT), session_path],
                text=True,
                capture_output=True,
                timeout=10,
                check=False,
            )
            if proc.returncode == 0:
                transcript_path = proc.stdout.strip().splitlines()[-1] if proc.stdout.strip() else ""
                log_hook("pre-compact", "ok", Path(session_path).name, payload)
            else:
                log_hook("pre-compact", "warn", proc.stderr.strip(), payload)
        except (OSError, subprocess.TimeoutExpired) as exc:
            log_hook("pre-compact", "warn", repr(exc), payload)
    try:
        snapshot_path = write_precompact_snapshot(session_path, payload, transcript_path)
        log_hook("pre-compact", "ok", f"state-snapshot {Path(snapshot_path).name}", payload)
    except Exception as exc:
        log_hook("pre-compact", "warn", f"state snapshot failed: {exc!r}", payload)
    if QMD_REFRESH.exists():
        try:
            subprocess.Popen(
                ["bash", str(QMD_REFRESH)],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError as exc:
            log_hook("pre-compact", "warn", f"qmd refresh queue failed: {exc}", payload)
    return 0


def subagent_start(data: dict[str, Any]) -> int:
    payload = normalize_payload(data)
    proc = run_script(VAULT_SCRIPTS / "subagent-context-hook.sh", payload, timeout=5)
    if proc is None or not proc.stdout.strip():
        log_hook("subagent-start", "skip", "subagent context missing", payload)
        return 0
    if proc.returncode != 0:
        log_hook("subagent-start", "warn", proc.stderr.strip(), payload)
        return 0
    log_hook("subagent-start", "ok", "context injected", payload)
    sys.stdout.write(proc.stdout if proc.stdout.endswith("\n") else proc.stdout + "\n")
    return 0


def stop(data: dict[str, Any]) -> int:
    payload = normalize_payload(data)
    cwd = str(payload.get("cwd") or os.getcwd())
    session_path = str(payload.get("transcript_path") or payload.get("session_path") or payload.get("sessionPath") or latest_session())
    stop_payload = {
        "session_id": payload.get("session_id") or (Path(session_path).stem if session_path else ""),
        "session_path": session_path,
        "transcript_path": session_path,
        "cwd": cwd,
        "stop_hook_active": bool(payload.get("stop_hook_active", False)),
    }
    completion = run_script(VAULT_SCRIPTS / "completion-check-hook.sh", stop_payload, timeout=15)
    if completion and completion.returncode == 2:
        reason = completion.stderr.strip() or "completion check blocked stop"
        return block(word_cap(reason, 120), "stop", payload)
    if completion and completion.returncode not in {0, 2}:
        log_hook("stop", "warn", completion.stderr.strip(), payload)

    checkpoint = run_script(VAULT_SCRIPTS / "auto-checkpoint-hook.sh", stop_payload, timeout=10)
    if checkpoint and checkpoint.returncode != 0:
        log_hook("stop", "warn", checkpoint.stderr.strip(), payload)

    run_observe("stop", "session-marker", run_command([str(VAULT_SCRIPTS / "session-marker-hook.sh"), "touch"], stop_payload, timeout=3), payload)

    try:
        subprocess.Popen(
            ["bash", str(STOP_WORKER), session_path, cwd],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        log_hook("stop", "ok", "queued background finalization", payload)
    except OSError as exc:
        log_hook("stop", "error", f"failed to queue worker: {exc}", payload)
    return 0


def main() -> int:
    event = sys.argv[1] if len(sys.argv) > 1 else ""
    data = read_input()
    event = event or str(data.get("hook_event_name") or data.get("event_name") or "")
    normalized = event.replace("-", "").replace("_", "").lower()
    handlers = {
        "sessionstart": session_start,
        "userpromptsubmit": user_prompt_submit,
        "pretooluse": pre_tool_use,
        "permissionrequest": permission_request,
        "posttooluse": post_tool_use,
        "precompact": pre_compact,
        "subagentstart": subagent_start,
        "stop": stop,
    }
    handler = handlers.get(normalized)
    if handler is None:
        log_hook("unknown", "skip", event, data)
        return 0
    try:
        return handler(data)
    except Exception as exc:
        log_hook(normalized or "unknown", "error", repr(exc), data)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
