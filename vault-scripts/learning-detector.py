#!/usr/bin/env python3
"""Scan a Claude Code JSONL session for learnable moments.

Detects user corrections, decisions, and discoveries via regex pattern matching.
Appends detected learnings to ~/vault/learnings-queue.jsonl for later review.

Usage: learning-detector.py <session.jsonl>
Designed to run as a background process — fast, no external dependencies.
"""

import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

QUEUE_FILE = Path.home() / "vault" / "learnings-queue.jsonl"

# --- Detection patterns ---
# Each tuple: (compiled_regex, confidence, category)

HIGH_PATTERNS = [
    (re.compile(r"\bno,?\s+don'?t\s+use\b", re.I), "correction"),
    (re.compile(r"\bactually,?\s+use\b", re.I), "correction"),
    (re.compile(r"\bthat'?s\s+wrong\b", re.I), "correction"),
    (re.compile(r"\bnever\s+(?:use|do|add|create|put|make)\b", re.I), "correction"),
    (re.compile(r"\balways\s+(?:use|do|add|create|put|make|prefer|run)\b", re.I), "correction"),
    (re.compile(r"\bstop\s+doing\b", re.I), "correction"),
    (re.compile(r"\bdon'?t\s+ever\b", re.I), "correction"),
    (re.compile(r"\buse\s+\S+\s+(?:not|instead\s+of)\s+\S+\b", re.I), "correction"),
    (re.compile(r"\binstead,?\s+(?:use|do|try)\b", re.I), "correction"),
    (re.compile(r"\bwrong\s+approach\b", re.I), "correction"),
    (re.compile(r"\bthat'?s\s+not\s+(?:how|what|right)\b", re.I), "correction"),
    (re.compile(r"\bplease\s+don'?t\b", re.I), "correction"),
]

MEDIUM_PATTERNS = [
    (re.compile(r"\blet'?s\s+go\s+with\b", re.I), "decision"),
    (re.compile(r"\bin\s+this\s+project,?\s+we\s+(?:always|never|prefer|use)\b", re.I), "decision"),
    (re.compile(r"\bthe\s+pattern\s+here\s+is\b", re.I), "decision"),
    (re.compile(r"\bwe\s+prefer\b", re.I), "decision"),
    (re.compile(r"\bour\s+convention\s+is\b", re.I), "decision"),
    (re.compile(r"\bwe\s+(?:always|never)\b", re.I), "decision"),
    (re.compile(r"\bthe\s+standard\s+here\s+is\b", re.I), "decision"),
    (re.compile(r"\bfor\s+this\s+project,?\s+(?:use|prefer|always)\b", re.I), "decision"),
]

LOW_PATTERNS = [
    (re.compile(r"\btil\b", re.I), "discovery"),
    (re.compile(r"\bremember\s+this\s+for\s+next\s+time\b", re.I), "discovery"),
    (re.compile(r"\bgood\s+to\s+know\b", re.I), "discovery"),
    (re.compile(r"\bkeep\s+in\s+mind\b", re.I), "discovery"),
    (re.compile(r"\bnote\s+(?:to|for)\s+(?:self|future|later)\b", re.I), "discovery"),
    (re.compile(r"\bworth\s+remembering\b", re.I), "discovery"),
]

# --- Agent insight patterns (assistant messages) ---
# These capture knowledge the agent discovered during work.

AGENT_INSIGHT_PATTERNS = [
    # Root cause analysis
    (re.compile(r"\b(?:root\s+cause|the\s+(?:real|actual|underlying)\s+(?:issue|problem|bug))\s+(?:is|was)\b", re.I), "HIGH", "root_cause"),
    (re.compile(r"\bfound\s+(?:the|it)\b.{0,30}\b(?:bug|issue|problem|cause)\b", re.I), "HIGH", "root_cause"),
    # Architecture/pattern discovery
    (re.compile(r"\bthis\s+(?:codebase|project|repo)\s+(?:uses|follows|has)\b", re.I), "MEDIUM", "pattern"),
    (re.compile(r"\bthe\s+pattern\s+(?:here|is|used)\b", re.I), "MEDIUM", "pattern"),
    (re.compile(r"\bexisting\s+(?:pattern|convention|approach)\b", re.I), "MEDIUM", "pattern"),
    # Fix explanations
    (re.compile(r"\bthe\s+fix\s+(?:is|was)\b", re.I), "HIGH", "fix"),
    (re.compile(r"\bfixed\s+by\b", re.I), "HIGH", "fix"),
    (re.compile(r"\b(?:this|the)\s+(?:broke|fails|failed)\s+because\b", re.I), "HIGH", "fix"),
    # Key findings
    (re.compile(r"\b(?:three|two|key)\s+bugs?\s+fixed\b", re.I), "HIGH", "summary"),
    (re.compile(r"\bhere'?s\s+(?:what|why)\b", re.I), "MEDIUM", "summary"),
    (re.compile(r"\bthe\s+(?:critical|important|key)\s+(?:issue|thing|insight|finding)\b", re.I), "HIGH", "summary"),
]


def hash_text(text: str) -> str:
    """Create a short hash for dedup."""
    return hashlib.sha256(text.strip().lower().encode()).hexdigest()[:16]


def load_existing_hashes() -> set:
    """Load hashes of existing queue entries for dedup."""
    hashes = set()
    if QUEUE_FILE.exists():
        try:
            for line in QUEUE_FILE.read_text().splitlines():
                if line.strip():
                    entry = json.loads(line)
                    hashes.add(hash_text(entry.get("trigger_text", "")))
        except (json.JSONDecodeError, OSError):
            pass
    return hashes


def extract_proposed_learning(text: str, category: str) -> str:
    """Extract a concise actionable learning from the trigger text."""
    # Strip conversational fluff
    text = text.strip()
    # Remove leading "No, " "Actually, " etc.
    text = re.sub(r"^(?:no,?\s*|actually,?\s*|please\s+|stop,?\s*)", "", text, flags=re.I)
    # Capitalize first letter
    if text:
        text = text[0].upper() + text[1:]
    # Truncate to reasonable length
    if len(text) > 200:
        text = text[:197] + "..."
    return text


def extract_context(text: str, match_start: int) -> str:
    """Get surrounding context for the match."""
    # Get the sentence containing the match
    start = max(0, text.rfind(".", 0, match_start) + 1)
    end = text.find(".", match_start)
    if end == -1:
        end = min(len(text), match_start + 150)
    else:
        end = min(end + 1, match_start + 200)
    return text[start:end].strip()


def extract_session_metadata(filepath: str) -> tuple:
    """Extract session_id, project, and cwd from JSONL file.

    Returns (session_id, project, cwd).
    """
    session_id = Path(filepath).stem
    project = "general"
    cwd = ""

    try:
        with open(filepath) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue

                if obj.get("sessionId") and session_id == Path(filepath).stem:
                    session_id = obj["sessionId"]
                if obj.get("cwd") and not cwd:
                    cwd = obj["cwd"]
                    parts = Path(cwd).parts
                    if parts:
                        project = parts[-1].lower()

                # Stop after finding metadata (usually in first few lines)
                if session_id != Path(filepath).stem and cwd:
                    break
    except OSError:
        pass

    return session_id, project, cwd


def is_agent_session(cwd: str) -> bool:
    """Return True if this session was a claude-flow agent sub-session.

    These are spawned in worktree paths and their "user messages"
    are programmatic prompts, not real human input.
    """
    return ".claude-flow/worktrees/" in cwd


def extract_user_messages(filepath: str) -> list:
    """Extract user message texts from a JSONL session file."""
    messages = []
    try:
        with open(filepath) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue

                if obj.get("type") != "user":
                    continue

                message = obj.get("message", {})
                content = message.get("content", "")

                if isinstance(content, str):
                    text = content.strip()
                elif isinstance(content, list):
                    text_parts = []
                    for block in content:
                        if isinstance(block, dict) and block.get("type") == "text":
                            text_parts.append(block.get("text", ""))
                        elif isinstance(block, str):
                            text_parts.append(block)
                    text = "\n".join(text_parts).strip()
                else:
                    continue

                # Skip very short messages, system/tool content, and
                # programmatic prompts (real user corrections are short)
                if len(text) > 5 and len(text) < 500 and not text.startswith("<"):
                    messages.append(text)
    except OSError:
        pass

    return messages


def extract_assistant_messages(filepath: str) -> list:
    """Extract assistant text messages from a JSONL session file."""
    messages = []
    try:
        with open(filepath) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue

                if obj.get("type") != "assistant":
                    continue

                message = obj.get("message", {})
                content = message.get("content", "")

                if isinstance(content, str):
                    text = content.strip()
                elif isinstance(content, list):
                    text_parts = []
                    for block in content:
                        if isinstance(block, dict) and block.get("type") == "text":
                            text_parts.append(block.get("text", ""))
                    text = "\n".join(text_parts).strip()
                else:
                    continue

                # Only capture substantive messages, capped at 2000 chars
                # (insights are in concise explanations, not full code dumps)
                if 50 < len(text) < 2000:
                    messages.append(text)
    except OSError:
        pass

    return messages


def detect_agent_insights(messages: list, session_id: str, project: str) -> list:
    """Scan assistant messages for knowledge worth capturing."""
    insights = []

    for text in messages:
        # Split long messages into paragraphs for better context extraction
        for para in text.split("\n\n"):
            para = para.strip()
            if len(para) < 30:
                continue

            for pattern, confidence, category in AGENT_INSIGHT_PATTERNS:
                match = pattern.search(para)
                if match:
                    insights.append({
                        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                        "session_id": session_id,
                        "project": project,
                        "confidence": confidence,
                        "category": category,
                        "trigger_text": para[:300],
                        "proposed_learning": extract_proposed_learning(para, category),
                        "context": extract_context(para, match.start()),
                        "status": "pending",
                        "source": "agent",
                    })
                    break  # One detection per paragraph

    return insights


def detect_learnings(messages: list, session_id: str, project: str) -> list:
    """Scan messages for learnable moments."""
    learnings = []

    for text in messages:
        # Check HIGH patterns
        for pattern, category in HIGH_PATTERNS:
            match = pattern.search(text)
            if match:
                learnings.append({
                    "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "session_id": session_id,
                    "project": project,
                    "confidence": "HIGH",
                    "category": category,
                    "trigger_text": text[:300],
                    "proposed_learning": extract_proposed_learning(text, category),
                    "context": extract_context(text, match.start()),
                    "status": "pending",
                })
                break  # One detection per message

        else:
            # Check MEDIUM patterns
            for pattern, category in MEDIUM_PATTERNS:
                match = pattern.search(text)
                if match:
                    learnings.append({
                        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                        "session_id": session_id,
                        "project": project,
                        "confidence": "MEDIUM",
                        "category": category,
                        "trigger_text": text[:300],
                        "proposed_learning": extract_proposed_learning(text, category),
                        "context": extract_context(text, match.start()),
                        "status": "pending",
                    })
                    break

            else:
                # Check LOW patterns
                for pattern, category in LOW_PATTERNS:
                    match = pattern.search(text)
                    if match:
                        learnings.append({
                            "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                            "session_id": session_id,
                            "project": project,
                            "confidence": "LOW",
                            "category": category,
                            "trigger_text": text[:300],
                            "proposed_learning": extract_proposed_learning(text, category),
                            "context": extract_context(text, match.start()),
                            "status": "pending",
                        })
                        break

    return learnings


def main():
    if len(sys.argv) < 2:
        print("Usage: learning-detector.py <session.jsonl>", file=sys.stderr)
        sys.exit(1)

    filepath = sys.argv[1]
    if not Path(filepath).is_file():
        print(f"File not found: {filepath}", file=sys.stderr)
        sys.exit(1)

    session_id, project, cwd = extract_session_metadata(filepath)

    # Skip claude-flow agent sub-sessions (their "user messages" are prompts)
    if is_agent_session(cwd):
        return

    messages = extract_user_messages(filepath)
    assistant_messages = extract_assistant_messages(filepath)

    if not messages and not assistant_messages:
        return

    learnings = detect_learnings(messages, session_id, project)

    # Also scan assistant messages for insights (root causes, patterns, fixes)
    learnings.extend(detect_agent_insights(assistant_messages, session_id, project))

    if not learnings:
        return

    # Dedup against existing queue
    existing_hashes = load_existing_hashes()
    new_learnings = []
    for learning in learnings:
        h = hash_text(learning["trigger_text"])
        if h not in existing_hashes:
            new_learnings.append(learning)
            existing_hashes.add(h)

    if not new_learnings:
        return

    # Append to queue
    QUEUE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(QUEUE_FILE, "a") as f:
        for learning in new_learnings:
            f.write(json.dumps(learning) + "\n")

    # Log to workflow audit trail
    log_file = Path.home() / "vault" / "logs" / "workflow.jsonl"
    log_file.parent.mkdir(parents=True, exist_ok=True)
    log_entry = json.dumps({
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "skill": "hook:learning-detector",
        "project": project,
        "task": f"detected {len(new_learnings)} learnings ({', '.join(l['confidence'] for l in new_learnings)})",
    })
    with open(log_file, "a") as f:
        f.write(log_entry + "\n")

    print(f"Detected {len(new_learnings)} new learnings from {Path(filepath).name}")


if __name__ == "__main__":
    main()
