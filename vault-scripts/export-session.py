#!/usr/bin/env python3
"""Convert a Claude Code JSONL session file to clean markdown with YAML frontmatter.

v2: Noise stripping, rich metadata extraction (model, tools, files, tokens, errors).
"""

import json
import sys
import os
import re
from collections import Counter
from datetime import datetime
from pathlib import Path

VAULT_SESSIONS = Path.home() / "vault" / "sessions"

# Tags to strip from all text content
NOISE_TAGS_RE = re.compile(
    r"<(?:command-name|command-message|command-args|local-command-stdout|"
    r"local-command-caveat|task-notification|system-reminder)>"
    r".*?"
    r"</(?:command-name|command-message|command-args|local-command-stdout|"
    r"local-command-caveat|task-notification|system-reminder)>",
    re.DOTALL,
)


def strip_noise(text: str) -> str:
    """Remove noise tags from text content."""
    return NOISE_TAGS_RE.sub("", text).strip()


def slugify(text: str) -> str:
    """Convert text to a filesystem-safe slug."""
    text = text.lower().strip()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    return text[:60].strip("-")


def _shorten_path(full_path: str, cwd: str) -> str:
    """Strip cwd prefix for shorter paths."""
    if cwd and full_path.startswith(cwd):
        rel = full_path[len(cwd):]
        return rel.lstrip("/")
    return full_path


def extract_first_user_message(messages: list) -> str:
    """Get the first real user message as a title hint."""
    for msg in messages:
        if msg["role"] == "user":
            first_line = msg["text"].split("\n")[0].strip()
            if len(first_line) > 10:
                return first_line[:120]
    return "untitled"


def parse_jsonl(filepath: str) -> dict:
    """Parse a Claude Code JSONL file and extract metadata + messages."""
    messages = []
    session_id = None
    slug = None
    version = None
    cwd = None
    git_branch = None
    timestamps = []
    model = None

    # Rich metadata accumulators
    tools_used = Counter()
    files_touched: dict[str, set[str]] = {}  # path -> set of tool names
    total_input_tokens = 0
    total_output_tokens = 0
    total_cache_creation = 0
    total_cache_read = 0
    errors: list[str] = []

    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            msg_type = obj.get("type")
            if msg_type in ("file-history-snapshot", "progress", "summary"):
                continue
            if obj.get("isMeta", False):
                continue

            # Collect metadata from any message
            if not session_id and obj.get("sessionId"):
                session_id = obj["sessionId"]
            if not slug and obj.get("slug"):
                slug = obj["slug"]
            if not version and obj.get("version"):
                version = obj["version"]
            if not cwd and obj.get("cwd"):
                cwd = obj["cwd"]
            if not git_branch and obj.get("gitBranch"):
                gb = obj["gitBranch"]
                if gb and gb != "HEAD":
                    git_branch = gb

            ts = obj.get("timestamp")
            if ts:
                timestamps.append(ts)

            if msg_type not in ("user", "assistant"):
                continue

            message = obj.get("message", {})
            role = message.get("role", msg_type)
            content = message.get("content", "")

            # Extract model from assistant messages
            if role == "assistant" and not model:
                m = message.get("model")
                if m:
                    model = m

            # Accumulate token usage from assistant messages
            if role == "assistant":
                usage = message.get("usage", {})
                total_input_tokens += usage.get("input_tokens", 0)
                total_output_tokens += usage.get("output_tokens", 0)
                total_cache_creation += usage.get("cache_creation_input_tokens", 0)
                total_cache_read += usage.get("cache_read_input_tokens", 0)

            # Process content blocks
            text_parts = []
            tool_annotations = []  # tool annotations for this message

            if isinstance(content, str):
                cleaned = strip_noise(content)
                if cleaned:
                    text_parts.append(cleaned)
            elif isinstance(content, list):
                for block in content:
                    if not isinstance(block, dict):
                        if isinstance(block, str):
                            cleaned = strip_noise(block)
                            if cleaned:
                                text_parts.append(cleaned)
                        continue

                    block_type = block.get("type")

                    if block_type == "thinking":
                        thinking = block.get("thinking", "").strip()
                        if thinking:
                            text_parts.append(f"<details><summary>Thinking</summary>\n\n{thinking}\n\n</details>")

                    elif block_type == "text":
                        cleaned = strip_noise(block.get("text", ""))
                        if cleaned:
                            # Skip system-reminder / tool_result wrappers
                            if cleaned.startswith("<system-reminder>"):
                                continue
                            if cleaned.startswith("<tool_result>") or cleaned.startswith("<function_results>"):
                                continue
                            text_parts.append(cleaned)

                    elif block_type == "tool_use":
                        tool_name = block.get("name", "unknown")
                        tools_used[tool_name] += 1
                        inp = block.get("input", {})

                        # Track files touched
                        fpath = inp.get("file_path") or inp.get("path")
                        if fpath and isinstance(fpath, str):
                            short = _shorten_path(fpath, cwd or "")
                            if short not in files_touched:
                                files_touched[short] = set()
                            files_touched[short].add(tool_name)

                        # Build tool annotation
                        if tool_name == "Bash":
                            cmd = inp.get("command", "")
                            first_line = cmd.split("\n")[0][:60] if cmd else ""
                            if fpath:
                                tool_annotations.append(f"Bash: {first_line}")
                            else:
                                tool_annotations.append(f"Bash: {first_line}")
                        elif fpath:
                            short = _shorten_path(fpath, cwd or "")
                            tool_annotations.append(f"{tool_name} → {short}")
                        else:
                            tool_annotations.append(tool_name)

                    elif block_type == "tool_result" and block.get("is_error"):
                        err_content = block.get("content", "")
                        err_text = ""
                        if isinstance(err_content, str):
                            err_text = err_content
                        elif isinstance(err_content, list):
                            for ec in err_content:
                                if isinstance(ec, dict) and ec.get("type") == "text":
                                    err_text = ec.get("text", "")
                                    break
                        if err_text:
                            errors.append(err_text[:200])

            if text_parts:
                combined = "\n\n".join(text_parts)
                messages.append({
                    "role": role,
                    "text": combined,
                    "tool_annotations": tool_annotations if role == "assistant" else [],
                })

    # Derive date
    date_str = None
    if timestamps:
        try:
            dt = datetime.fromisoformat(timestamps[0].replace("Z", "+00:00"))
            date_str = dt.strftime("%Y-%m-%d")
        except (ValueError, TypeError):
            pass
    if not date_str:
        date_str = datetime.now().strftime("%Y-%m-%d")

    # Derive project from cwd
    project = "general"
    if cwd:
        parts = Path(cwd).parts
        if len(parts) > 0:
            project = parts[-1].lower()

    return {
        "session_id": session_id or Path(filepath).stem,
        "slug": slug or "",
        "version": version or "",
        "date": date_str,
        "project": project,
        "cwd": cwd or "",
        "git_branch": git_branch or "",
        "model": model or "",
        "message_count": len(messages),
        "messages": messages,
        "tools_used": dict(tools_used.most_common()),
        "files_touched": {k: sorted(v) for k, v in files_touched.items()},
        "total_input_tokens": total_input_tokens,
        "total_output_tokens": total_output_tokens,
        "total_cache_creation": total_cache_creation,
        "total_cache_read": total_cache_read,
        "total_tokens": total_input_tokens + total_output_tokens,
        "errors": errors,
    }


def _yaml_list(items: list[str]) -> str:
    """Format a list for YAML frontmatter inline."""
    escaped = [f'"{item}"' if " " in item or ":" in item else item for item in items]
    return "[" + ", ".join(escaped) + "]"


def render_markdown(data: dict) -> str:
    """Render parsed session data as markdown with YAML frontmatter."""
    title = extract_first_user_message(data["messages"])

    lines = []
    # Frontmatter
    lines.append("---")
    lines.append(f"date: {data['date']}")
    lines.append(f"project: {data['project']}")
    lines.append(f"session_id: {data['session_id']}")
    lines.append(f"slug: {data['slug']}")
    lines.append(f"version: {data['version']}")
    lines.append(f"cwd: {data['cwd']}")
    if data["git_branch"]:
        lines.append(f"git_branch: {data['git_branch']}")
    if data["model"]:
        lines.append(f"model: {data['model']}")
    lines.append(f"message_count: {data['message_count']}")
    if data["tools_used"]:
        lines.append(f"tools_used: {_yaml_list(list(data['tools_used'].keys()))}")
    if data["files_touched"]:
        files_list = sorted(data["files_touched"].keys())[:20]  # cap at 20
        lines.append(f"files_touched: {_yaml_list(files_list)}")
    if data["total_tokens"]:
        lines.append(f"total_tokens: {data['total_tokens']}")
    lines.append(f'title: "{title}"')
    lines.append("---")
    lines.append("")
    lines.append(f"# {title}")
    lines.append("")

    # Messages with tool annotations
    for msg in data["messages"]:
        role_label = "User" if msg["role"] == "user" else "Assistant"
        annotations = msg.get("tool_annotations", [])
        if annotations:
            # Show up to 3 annotations inline
            ann_str = "; ".join(annotations[:3])
            if len(annotations) > 3:
                ann_str += f" +{len(annotations) - 3} more"
            lines.append(f"## {role_label} [tool: {ann_str}]")
        else:
            lines.append(f"## {role_label}")
        lines.append("")
        lines.append(msg["text"])
        lines.append("")

    # Summary section
    lines.append("## Summary")
    lines.append("")

    # Files Touched
    if data["files_touched"]:
        lines.append("### Files Touched")
        for fpath, tool_set in sorted(data["files_touched"].items()):
            tools_str = ", ".join(sorted(tool_set))
            lines.append(f"- {fpath} ({tools_str})")
        lines.append("")

    # Tools Used
    if data["tools_used"]:
        lines.append("### Tools Used")
        for tool, count in data["tools_used"].items():
            lines.append(f"- {tool}: {count}")
        lines.append("")

    # Token Usage
    if data["total_tokens"]:
        lines.append("### Token Usage")
        lines.append(f"- Input: {data['total_input_tokens']:,}")
        lines.append(f"- Output: {data['total_output_tokens']:,}")
        lines.append(f"- Total: {data['total_tokens']:,}")
        lines.append("")

    # Errors
    lines.append("### Errors")
    if data["errors"]:
        for err in data["errors"][:10]:  # cap at 10
            lines.append(f"- {err}")
    else:
        lines.append("- None")
    lines.append("")

    return "\n".join(lines)


def _extract_message_count(filepath: Path) -> int:
    """Extract message_count from YAML frontmatter of an existing export."""
    try:
        text = filepath.read_text(encoding="utf-8")
        match = re.search(r"^message_count:\s*(\d+)", text, re.MULTILINE)
        return int(match.group(1)) if match else 0
    except (OSError, ValueError):
        return 0


def _merge_post_compaction(output_path: Path, new_data: dict, existing_count: int) -> bool:
    """Append post-compaction messages to an existing richer export.

    The existing file has the pre-compaction transcript (more messages).
    The JSONL has fewer messages (compacted beginning + new tail).
    We detect the overlap by matching the last few messages of the existing
    export against the JSONL messages, then append anything new.

    Returns True if the file was updated, False if nothing new to add.
    """
    existing_text = output_path.read_text(encoding="utf-8")
    new_msgs = new_data["messages"]

    if not new_msgs:
        return False

    # Extract the existing message texts (just the raw text after ## User/## Assistant headers)
    # We'll match against the last N messages to find where the JSONL picks up
    existing_msg_texts = []
    for match in re.finditer(r"^## (?:User|Assistant).*?\n\n(.*?)(?=\n## (?:User|Assistant)|\n## Summary)", existing_text, re.DOTALL | re.MULTILINE):
        existing_msg_texts.append(match.group(1).strip())

    if not existing_msg_texts:
        return False

    # Find overlap: look for the first JSONL message that matches the last existing message
    # then take everything after it
    last_existing = existing_msg_texts[-1]
    overlap_idx = -1
    for i, msg in enumerate(new_msgs):
        # Fuzzy match: compare first 200 chars to handle minor formatting differences
        if msg["text"][:200].strip() == last_existing[:200].strip():
            overlap_idx = i
            break

    if overlap_idx < 0:
        # No overlap found. This could mean:
        # 1. Compaction was so aggressive that no messages survive from the original
        # 2. This is a subagent JSONL with completely different messages
        # To be safe, only append if we find at least ONE message from the JSONL
        # somewhere in the existing export (proves same conversation continuity).
        found_any = False
        for msg in new_msgs:
            snippet = msg["text"][:200].strip()
            for et in existing_msg_texts:
                if et[:200].strip() == snippet:
                    found_any = True
                    break
            if found_any:
                break
        if not found_any:
            # No overlap at all — likely a subagent or unrelated JSONL, skip
            return False
        # Some overlap exists but last message didn't match — all JSONL msgs
        # are likely already in the export
        return False
    else:
        # Take messages after the overlap point
        tail_msgs = new_msgs[overlap_idx + 1:]

    if not tail_msgs:
        print(f"  Merge: no new messages after overlap (existing {existing_count}, JSONL {new_data['message_count']})")
        return False

    # Build the new message lines
    new_lines = []
    for msg in tail_msgs:
        role_label = "User" if msg["role"] == "user" else "Assistant"
        annotations = msg.get("tool_annotations", [])
        if annotations:
            ann_str = "; ".join(annotations[:3])
            if len(annotations) > 3:
                ann_str += f" +{len(annotations) - 3} more"
            new_lines.append(f"## {role_label} [tool: {ann_str}]")
        else:
            new_lines.append(f"## {role_label}")
        new_lines.append("")
        new_lines.append(msg["text"])
        new_lines.append("")

    tail_md = "\n".join(new_lines)

    # Insert before ## Summary
    summary_marker = "\n## Summary\n"
    if summary_marker in existing_text:
        updated = existing_text.replace(summary_marker, "\n" + tail_md + summary_marker, 1)
    else:
        # No summary section — just append
        updated = existing_text.rstrip() + "\n\n" + tail_md

    # Update the message_count in frontmatter
    total_count = existing_count + len(tail_msgs)
    updated = re.sub(
        r"^message_count:\s*\d+",
        f"message_count: {total_count}",
        updated,
        count=1,
        flags=re.MULTILINE,
    )

    if updated == existing_text:
        return False

    output_path.write_text(updated, encoding="utf-8")
    print(f"  Merged: +{len(tail_msgs)} post-compaction msgs (now {total_count} total)")
    return True


def export_session(jsonl_path: str, precompact: bool = False, cleanup_stale: bool = True) -> str:
    """Export a single JSONL session to markdown. Returns output path or empty string."""
    data = parse_jsonl(jsonl_path)

    # Skip noise-only sessions
    has_assistant = any(m["role"] == "assistant" for m in data["messages"])
    if data["message_count"] < 3 or not has_assistant:
        # Clean up previously exported file if it exists (skip in batch mode)
        if cleanup_stale:
            _cleanup_stale(data, jsonl_path)
        return ""

    # Build filename: YYYY-MM-DD_project_slug_id.md
    parts = [data["date"], data["project"]]
    if data["slug"]:
        parts.append(slugify(data["slug"]))
    parts.append(data["session_id"][:8])
    filename = "_".join(parts) + ".md"

    VAULT_SESSIONS.mkdir(parents=True, exist_ok=True)
    output_path = VAULT_SESSIONS / filename

    # Merge/overwrite strategy for existing exports
    if not precompact and output_path.exists():
        existing_count = _extract_message_count(output_path)
        if existing_count >= data["message_count"]:
            # Existing is richer or equal — try to merge post-compaction tail
            if existing_count > data["message_count"]:
                merged = _merge_post_compaction(output_path, data, existing_count)
                if merged:
                    return str(output_path)
            return ""

    md = render_markdown(data)

    # Skip write if file exists with identical content (avoids qmd re-index breakage)
    if output_path.exists() and output_path.read_text(encoding="utf-8") == md:
        return ""

    output_path.write_text(md, encoding="utf-8")

    return str(output_path)


def _cleanup_stale(data: dict, jsonl_path: str):
    """Delete previously exported file for a session that's now filtered out."""
    if not VAULT_SESSIONS.exists():
        return
    sid_prefix = (data.get("session_id") or Path(jsonl_path).stem)[:8]
    for f in VAULT_SESSIONS.glob(f"*{sid_prefix}.md"):
        f.unlink()
        print(f"  Cleaned up stale: {f.name}")


def main():
    if len(sys.argv) < 2:
        print("Usage: export-session.py <path-to-session.jsonl|--batch-dir DIR> [--precompact]", file=sys.stderr)
        sys.exit(1)

    precompact = "--precompact" in sys.argv

    # Batch mode: process all JSONLs under a directory, sorted by size (smallest first,
    # so larger/richer files overwrite smaller ones and the final state is stable).
    if sys.argv[1] == "--batch-dir":
        if len(sys.argv) < 3:
            print("Usage: export-session.py --batch-dir DIR [--precompact]", file=sys.stderr)
            sys.exit(1)
        base = Path(sys.argv[2])
        jsonl_files = sorted(
            (f for f in base.rglob("*.jsonl") if "/subagents/" not in str(f)),
            key=lambda p: p.stat().st_size,
        )
        exported = 0
        merged = 0
        skipped = 0
        for jf in jsonl_files:
            try:
                result = export_session(str(jf), precompact=precompact, cleanup_stale=False)
                if result:
                    exported += 1
                else:
                    skipped += 1
            except Exception as e:
                print(f"  Error processing {jf.name}: {e}")
                skipped += 1
        print(f"Batch done: {exported} exported, {skipped} skipped, {len(jsonl_files)} total")
    else:
        jsonl_path = sys.argv[1]
        if not os.path.isfile(jsonl_path):
            print(f"File not found: {jsonl_path}", file=sys.stderr)
            sys.exit(1)

        output = export_session(jsonl_path, precompact=precompact)
        if output:
            print(f"Exported: {output}")
        else:
            print(f"Skipped (noise-only or kept richer): {jsonl_path}")


if __name__ == "__main__":
    main()
