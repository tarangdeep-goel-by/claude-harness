#!/usr/bin/env python3
"""skill_analyzer.py — offline skill-quality + routing telemetry from a session JSONL.

Runs in the session-export pipeline (no hot-path cost). For one session it emits:

  ~/vault/logs/skills.jsonl   — one record per skill/agent invocation window:
      skill, source (auto|explicit), output_tokens, tool_calls, errors,
      duration_ms, correction_next  → drives COST and CORRECTION-RATE.

  ~/vault/logs/routing.jsonl  — one record per real user turn whose prompt
      matched a skill's triggers:  verdict (ok|missed|misfire), matched, fired
      → drives ROUTING-ADHERENCE and (with the registry) the DEAD-SKILL list.

Two invocation paths are both captured:
  1. model calls the Skill tool          → source=auto
  2. user types a /slash-command skill   → source=explicit  (workflow.jsonl misses these)

Idempotent: re-running on the same (growing) JSONL dedups by a stable id, so the
Stop/PreCompact/debounce re-runs never double-count.

Usage: skill_analyzer.py <session.jsonl>
"""

import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

LOGS = Path.home() / "vault" / "logs"
SKILLS_SINK = LOGS / "skills.jsonl"
ROUTING_SINK = LOGS / "routing.jsonl"

# Reuse the correction signal from learning-detector (the rework/quality signal).
CORRECTION_RE = [
    re.compile(p, re.I) for p in (
        r"\bno,?\s+don'?t\b", r"\bactually,?\s+use\b", r"\bthat'?s\s+wrong\b",
        r"\bthat'?s\s+not\s+(?:how|what|right)\b", r"\bwrong\s+approach\b",
        r"\binstead,?\s+(?:use|do|try)\b", r"\bstop\s+doing\b",
        r"\bnot\s+what\s+i\b", r"\bdon'?t\s+(?:do|use)\s+that\b",
        r"\bundo\b", r"\brevert\b", r"\bredo\b",
    )
]

# Single-word triggers this generic are too noisy to count as routing signals.
GENERIC_STOPWORDS = {
    "find", "save", "run", "status", "search", "look", "show", "get", "make",
    "create", "update", "check", "build", "note", "write", "process", "new",
    "what", "how", "the", "this", "add", "use", "help",
}


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _ts_ms(ts):
    if not ts:
        return None
    try:
        return int(datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp() * 1000)
    except (ValueError, TypeError):
        return None


# ── Skill registry + trigger map ────────────────────────────────────────

def _parse_frontmatter(text):
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end < 0:
        return {}
    fm = {}
    for line in text[3:end].splitlines():
        m = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
        if m:
            fm[m.group(1).strip()] = m.group(2).strip().strip('"').strip("'")
    return fm


def load_registry(cwd):
    """Return {skill_name: set(trigger_phrases)} from global + project skills."""
    reg = {}
    dirs = [Path.home() / ".claude" / "skills"]
    if cwd:
        dirs.append(Path(cwd) / ".claude" / "skills")
    for base in dirs:
        if not base.is_dir():
            continue
        for sk in base.glob("*/SKILL.md"):
            try:
                text = sk.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            fm = _parse_frontmatter(text)
            name = fm.get("name") or sk.parent.name
            desc = fm.get("description", "")
            triggers = set()
            # quoted phrases in the description are the explicit trigger examples
            for q in re.findall(r'["“]([^"”]{3,40})["”]', desc):
                q = q.strip().lower()
                if len(q) >= 4:
                    triggers.add(q)
            # the skill name itself (kebab → spaced) as a phrase
            triggers.add(name.replace("-", " ").lower())
            # keep only phrases that are multi-word or specific single words
            triggers = {
                t for t in triggers
                if (" " in t) or (len(t) >= 5 and t not in GENERIC_STOPWORDS)
            }
            reg.setdefault(name, set()).update(triggers)
    return reg


def match_skills(prompt, registry):
    """Skills whose triggers fire on this prompt.

    Multi-word phrases match anywhere. Single bare words (e.g. a skill name like
    "analysis"/"recall") only count near the START of the prompt — an imperative
    "recall X", not conversational "our analysis of X" — to keep the routing
    metric precise instead of flagging every passing mention.
    """
    p = prompt.lower()
    head = " ".join(p.split()[:5])
    hits = []
    for name, trigs in registry.items():
        for t in trigs:
            if " " in t:
                if t in p:
                    hits.append(name)
                    break
            else:
                if re.search(r"\b" + re.escape(t) + r"\b", head):
                    hits.append(name)
                    break
    return hits


# ── Session parsing into turns ──────────────────────────────────────────

def _text_of(content):
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = []
        for b in content:
            if isinstance(b, dict) and b.get("type") == "text":
                parts.append(b.get("text", ""))
            elif isinstance(b, str):
                parts.append(b)
        return "\n".join(parts).strip()
    return ""


def _is_tool_result(content):
    return isinstance(content, list) and any(
        isinstance(b, dict) and b.get("type") == "tool_result" for b in content
    )


def parse_turns(filepath):
    """Segment a session into human turns with attributed work + invocations."""
    session_id = Path(filepath).stem
    cwd = ""
    turns = []
    cur = None
    seq = 0

    def close():
        nonlocal cur
        if cur is not None:
            turns.append(cur)
            cur = None

    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                o = json.loads(line)
            except json.JSONDecodeError:
                continue
            if o.get("sessionId") and session_id == Path(filepath).stem:
                session_id = o["sessionId"]
            if o.get("cwd") and not cwd:
                cwd = o["cwd"]
            mtype = o.get("type")
            msg = o.get("message", {}) or {}
            content = msg.get("content", "")
            ts = o.get("timestamp")

            if mtype == "user":
                if o.get("isMeta"):
                    continue
                if _is_tool_result(content):
                    if cur is not None and ts:
                        cur["last_ts"] = ts
                    continue
                raw = content if isinstance(content, str) else json.dumps(content)
                slash = re.search(r"<command-name>\s*/?([\w-]+)", raw)
                text = _text_of(content)
                # ignore system/hook injected user blocks with no human text
                if not slash and (not text or text.startswith("<")):
                    continue
                close()
                cur = {
                    "prompt": (text or "")[:500],
                    "ts": ts,
                    "last_ts": ts,
                    "is_slash": bool(slash),
                    "slash_name": slash.group(1) if slash else None,
                    "invocations": [],   # (skill, source)
                    "out_tokens": 0,
                    "tool_calls": 0,
                    "errors": 0,
                }
            elif mtype == "assistant":
                if cur is None:
                    continue
                if ts:
                    cur["last_ts"] = ts
                usage = msg.get("usage", {}) or {}
                cur["out_tokens"] += usage.get("output_tokens", 0)
                if isinstance(content, list):
                    for b in content:
                        if not isinstance(b, dict):
                            continue
                        bt = b.get("type")
                        if bt == "tool_use":
                            nm = b.get("name", "")
                            if nm == "Skill":
                                sk = (b.get("input", {}) or {}).get("skill", "?")
                                cur["invocations"].append((sk, "auto", "skill"))
                            elif nm == "Task":
                                at = (b.get("input", {}) or {}).get("subagent_type", "agent")
                                cur["invocations"].append((at, "auto", "agent"))
                            else:
                                cur["tool_calls"] += 1
                        elif bt == "tool_result" and b.get("is_error"):
                            cur["errors"] += 1
            else:
                continue
    close()
    return session_id, cwd, turns


# ── Dedup ───────────────────────────────────────────────────────────────

def _load_ids(path, key="id"):
    ids = set()
    if path.exists():
        try:
            for ln in path.read_text().splitlines():
                if ln.strip():
                    ids.add(json.loads(ln).get(key))
        except (OSError, json.JSONDecodeError):
            pass
    return ids


def main():
    if len(sys.argv) < 2:
        print("Usage: skill_analyzer.py <session.jsonl>", file=sys.stderr)
        sys.exit(1)
    fp = sys.argv[1]
    if not Path(fp).is_file():
        print(f"File not found: {fp}", file=sys.stderr)
        sys.exit(1)

    session_id, cwd, turns = parse_turns(fp)
    if not turns:
        return
    if ".claude-flow/worktrees/" in cwd:   # programmatic agent sub-session
        return
    project = Path(cwd).parts[-1].lower() if cwd else "general"
    registry = load_registry(cwd)
    valid_skill_names = set(registry.keys())

    skill_recs, routing_recs = [], []
    seq = 0
    for i, t in enumerate(turns):
        # resolve all invocations for this turn (slash path + tool path)
        invs = list(t["invocations"])
        if t["is_slash"] and t["slash_name"] in valid_skill_names:
            invs.insert(0, (t["slash_name"], "explicit", "skill"))
        # does the NEXT human turn look like a correction? → rework signal
        corr_next = False
        if i + 1 < len(turns):
            nxt = turns[i + 1]["prompt"]
            corr_next = any(rx.search(nxt) for rx in CORRECTION_RE)
        n = max(1, len(invs))
        d_ms = None
        a, b = _ts_ms(t["ts"]), _ts_ms(t["last_ts"])
        if a is not None and b is not None and b >= a:
            d_ms = b - a
        for (name, source, kind) in invs:
            seq += 1
            skill_recs.append({
                "id": hashlib.sha256(f"{session_id}:{seq}:{name}".encode()).hexdigest()[:16],
                "ts": t["ts"] or now_iso(),
                "session": session_id[:8],
                "project": project,
                "kind": kind,
                "skill": name,
                "source": source,
                "output_tokens": t["out_tokens"] // n,
                "tool_calls": t["tool_calls"] // n,
                "errors": t["errors"],
                "duration_ms": d_ms,
                "correction_next": corr_next,
                "multi": len(invs) > 1,
            })
        # routing verdict — only for genuine (non-slash) human prompts
        if not t["is_slash"] and t["prompt"]:
            matched = match_skills(t["prompt"], registry)
            fired = [nm for (nm, _, k) in invs if k == "skill"]
            verdict = None
            if matched:
                verdict = "ok" if fired else "missed"
            elif fired:
                verdict = "misfire"   # fired with no matching trigger (low confidence)
            if verdict:
                routing_recs.append({
                    "id": hashlib.sha256(f"{session_id}:r:{i}".encode()).hexdigest()[:16],
                    "ts": t["ts"] or now_iso(),
                    "session": session_id[:8],
                    "project": project,
                    "verdict": verdict,
                    "matched": sorted(set(matched)),
                    "fired": sorted(set(fired)),
                    "prompt": t["prompt"][:160],
                })

    LOGS.mkdir(parents=True, exist_ok=True)
    new_s = [r for r in skill_recs if r["id"] not in _load_ids(SKILLS_SINK)]
    new_r = [r for r in routing_recs if r["id"] not in _load_ids(ROUTING_SINK)]
    if new_s:
        with open(SKILLS_SINK, "a") as f:
            for r in new_s:
                f.write(json.dumps(r) + "\n")
    if new_r:
        with open(ROUTING_SINK, "a") as f:
            for r in new_r:
                f.write(json.dumps(r) + "\n")
    print(f"skill_analyzer: +{len(new_s)} invocations, +{len(new_r)} routing verdicts "
          f"from {Path(fp).name}")


if __name__ == "__main__":
    main()
