#!/usr/bin/env python3
"""memory_health.py — read-only quality rollup for the memory corpus.

Reports how the memory corpus is doing across seven facets + a one-line verdict:
  - Capture       — memory-infer runs, candidates yielded, yield distribution
  - Approval      — applied/(applied+dismissed) over resolved queue entries
  - Invalidations — queue kind=invalidation, split stale-90d vs overlap
  - Utilization   — corpus read coverage from memory-consulted.json
  - Corpus shape  — frontmatter adoption, type/confidence dist, last_verified age
  - Hook health   — per memory-hook run count, error rate, mean duration
  - Issues        — never-consulted>60d, fastest-staling, zero-yield, adoption %

Pure read: never mutates the corpus, queue, or logs. Degrades gracefully on every
missing source (prints "(no data yet)", never errors). Mirrors the style of
infra_health.py (event-sink rollup) and apply_memory.py (corpus constants).

Usage:
  memory_health.py           # text report to stdout
  memory_health.py --json    # one JSON object to stdout (for /memory review)
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime, timezone

# ── Constants (copied from apply_memory.py to stay self-contained — no cross-import) ──
# Project-scoped memory dir, derived from CLAUDE_PROJECT_DIR (or cwd) — portable, matches
# Claude Code's per-project memory layout. Override with --memory-dir.
_CPD = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
_proj_slug = "-" + _CPD.lstrip("/").replace("/", "-")
DEFAULT_MEMORY_DIR = os.path.join(os.path.expanduser("~/.claude/projects"), _proj_slug, "memory")
CONF_RANK = {"high": 0, "medium": 1, "low": 2}  # lower sorts first

HOME = os.path.expanduser("~")
LOGS = f"{HOME}/vault/logs"
QUEUE_PATH = f"{HOME}/vault/memory-review-queue.jsonl"
CONSULTED_PATH = f"{LOGS}/memory-consulted.json"
STALENESS_STATE_PATH = f"{LOGS}/memory-staleness-state.json"

MEMORY_HOOKS = {"memory-infer", "memory-validate", "memory-staleness", "memory-consulted"}
SKIP_FILES = {"MEMORY.md", "SCHEMA.md", "_shared.md"}

# Verdict flag thresholds
HOOK_ERROR_RATE_FLAG = 0.10      # >10% error rate on any memory hook
ADOPTION_FLAG = 0.10             # canonical / total < 10%
NEVER_CONSULTED_FLAG = 0.50      # >50% of corpus never consulted

APPENDED_RE = re.compile(r"appended=(\d+)")


# ── Shared helpers (mirrors infra_health.py) ───────────────────────────
def parse_ts(d: dict) -> float | None:
    """Parse a row's timestamp to epoch seconds. Handles ISO (with/without Z)
    and an explicit ts_epoch field. Returns None if unparseable."""
    if "ts_epoch" in d:
        try:
            return float(d["ts_epoch"])
        except (TypeError, ValueError):
            pass
    ts = d.get("ts", "")
    if not ts:
        return None
    try:
        return datetime.fromisoformat(str(ts).replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def read_jsonl(path: str):
    """Yield parsed JSON rows from a JSONL file. Silently skips bad lines.
    Yields nothing if the file is absent."""
    if not os.path.exists(path):
        return
    with open(path) as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            try:
                yield json.loads(ln)
            except Exception:
                continue


def _days_since(date_str: str, now: float) -> int | None:
    """Days between an ISO YYYY-MM-DD date and `now`. None if unparseable."""
    if not date_str:
        return None
    try:
        d = datetime.strptime(date_str.strip()[:10], "%Y-%m-%d")
    except Exception:
        return None
    return int((now - d.timestamp()) // 86400)


def _duration_s(d: dict) -> float | None:
    """Normalize a hook row's duration to seconds. memory-validate uses
    duration_ms; the other memory hooks use duration_s."""
    if "duration_s" in d:
        try:
            return float(d["duration_s"])
        except (TypeError, ValueError):
            return None
    if "duration_ms" in d:
        try:
            return float(d["duration_ms"]) / 1000.0
        except (TypeError, ValueError):
            return None
    return None


# ── Frontmatter parser (minimal, schema-aware) ────────────────────────
def parse_frontmatter(text: str) -> tuple[dict, str]:
    """Parse a YAML-ish frontmatter block. Returns (fields, classification).

    classification:
      'canonical' — top-level name+description AND a `metadata:` sub-map
      'flat'      — top-level name+description, no `metadata:` sub-map
      'none'      — no frontmatter delimiters at all

    Handles the schema's flat keys plus the indented `metadata:` block. Not a
    general YAML parser — sufficient for this corpus's two shapes.
    """
    if not text.startswith("---"):
        return {}, "none"
    lines = text.splitlines()
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return {}, "none"
    fm: dict = {}
    metadata: dict = {}
    in_meta = False
    for ln in lines[1:end]:
        stripped = ln.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if not ln.startswith((" ", "\t")) and stripped.rstrip(":") == "metadata":
            in_meta = True
            continue
        if in_meta and (ln.startswith("  ") or ln.startswith("\t")):
            k, _, v = stripped.partition(":")
            if k:
                metadata[k.strip()] = v.strip()
            continue
        # dedent → leaving the metadata block
        if in_meta:
            in_meta = False
        if not ln.startswith((" ", "\t")):
            k, _, v = ln.partition(":")
            if k:
                fm[k.strip()] = v.strip()
    if metadata:
        fm["metadata"] = metadata
    has_name_desc = "name" in fm and "description" in fm
    if "metadata" in fm and has_name_desc:
        return fm, "canonical"
    if has_name_desc:
        return fm, "flat"
    return fm, "none"


def _corpus_files(memory_dir: str) -> list[str]:
    """Eligible corpus files: *.md in the dir, skipping MEMORY.md, SCHEMA.md,
    _shared.md, dotfiles, and any legacy/ subdir."""
    out = []
    for p in sorted(glob.glob(os.path.join(memory_dir, "*.md"))):
        name = os.path.basename(p)
        if name in SKIP_FILES:
            continue
        if name.startswith("."):
            continue
        out.append(p)
    return out


# ── Collectors — each returns a dict that both renderers consume ───────
def collect_capture() -> dict:
    """memory-infer hook: run count, total candidates (sum appended=N),
    yield distribution across runs."""
    runs = 0
    total_candidates = 0
    zero_yield = 0
    per_run: list[int] = []
    for d in read_jsonl(f"{LOGS}/hooks.jsonl"):
        if d.get("hook") != "memory-infer":
            continue
        runs += 1
        m = APPENDED_RE.search(str(d.get("detail", "")))
        n = int(m.group(1)) if m else 0
        total_candidates += n
        per_run.append(n)
        if n == 0:
            zero_yield += 1
    dist = {0: 0, 1: 0, 2: 0, "3+": 0}
    for n in per_run:
        if n >= 3:
            dist["3+"] += 1
        else:
            dist[n] += 1
    return {
        "runs": runs,
        "total_candidates": total_candidates,
        "yield_distribution": dist,
        "zero_yield_runs": zero_yield,
        "per_run": per_run,
    }


def collect_approval() -> dict:
    """Queue: applied/(applied+dismissed) over resolved; pending separate."""
    applied = dismissed = pending_candidates = 0
    for d in read_jsonl(QUEUE_PATH):
        if d.get("kind") != "memory_candidate":
            continue
        st = d.get("status", "pending")
        if st == "applied":
            applied += 1
        elif st == "dismissed":
            dismissed += 1
        else:
            pending_candidates += 1
    resolved = applied + dismissed
    rate = (applied / resolved) if resolved else None
    return {
        "applied": applied,
        "dismissed": dismissed,
        "pending": pending_candidates,
        "resolved": resolved,
        "rate": rate,
    }


def collect_invalidations() -> dict:
    """Queue kind=invalidation, split stale-90d vs overlap (from description)."""
    stale = overlap = pending = 0
    examples: list[str] = []
    for d in read_jsonl(QUEUE_PATH):
        if d.get("kind") != "invalidation":
            continue
        desc = str(d.get("description", ""))
        if desc.startswith("overlap-with:") or "overlap" in desc.lower():
            overlap += 1
        else:
            stale += 1
        if d.get("status") == "pending":
            pending += 1
        examples.append(d.get("name", "?"))
    return {"stale_90d": stale, "overlap": overlap, "total": stale + overlap,
            "pending": pending, "examples": examples[:10]}


def collect_utilization(corpus_paths: list[str]) -> dict:
    """From memory-consulted.json: % corpus never consulted, top-5, last-30d count."""
    if not os.path.exists(CONSULTED_PATH):
        return {"available": False}
    try:
        data = json.load(open(CONSULTED_PATH))
    except Exception:
        return {"available": False}
    now = time.time()
    consulted_in_30d = 0
    counts: list[tuple[str, int, str]] = []
    for rel, info in data.items():
        try:
            cnt = int(info.get("count", 0))
        except Exception:
            cnt = 0
        last = info.get("last_seen", "")
        age = _days_since(last, now)
        if age is not None and age <= 30:
            consulted_in_30d += 1
        counts.append((rel, cnt, last))
    counts.sort(key=lambda x: -x[1])
    # Corpus coverage by basename (consulted keys are relpaths; match on basename).
    consulted_basenames = {os.path.basename(rel) for rel in data.keys()}
    corpus_basenames = {os.path.basename(p) for p in corpus_paths}
    consulted_corpus = corpus_basenames & consulted_basenames
    never = corpus_basenames - consulted_corpus
    never_pct = (len(never) / len(corpus_basenames)) if corpus_basenames else 0.0
    return {
        "available": True,
        "corpus_total": len(corpus_basenames),
        "consulted": len(consulted_corpus),
        "never_consulted": len(never),
        "never_consulted_pct": never_pct,
        "consulted_30d": consulted_in_30d,
        "top5": [{"relpath": r, "count": c, "last_seen": l} for r, c, l in counts[:5]],
        "never_consulted_basenames": sorted(never),
    }


def collect_corpus(memory_dir: str) -> dict:
    """Corpus shape: frontmatter adoption, type/confidence dist, last_verified age."""
    paths = _corpus_files(memory_dir)
    total = len(paths)
    canonical = flat = nofm = 0
    types: Counter = Counter()
    confs: Counter = Counter()
    age_buckets = {"none": 0, "<30d": 0, "30-90d": 0, ">90d": 0}
    superseded_by = 0
    now = time.time()
    # for fastest-staling: high-confidence files by age desc
    high_conf_aged: list[tuple[int, str, str]] = []  # (age_days, name, last_verified)
    for p in paths:
        try:
            txt = open(p).read()
        except Exception:
            continue
        fm, klass = parse_frontmatter(txt)
        if klass == "canonical":
            canonical += 1
        elif klass == "flat":
            flat += 1
        else:
            nofm += 1
        meta = fm.get("metadata", {}) if isinstance(fm.get("metadata"), dict) else {}
        t = (meta.get("type") or fm.get("type") or "unknown").strip().lower()
        types[t] += 1
        c = (meta.get("confidence") or fm.get("confidence") or "unknown").strip().lower()
        confs[c] += 1
        lv = meta.get("last_verified") or fm.get("last_verified") or ""
        age = _days_since(lv, now)
        if age is None:
            age_buckets["none"] += 1
        elif age < 30:
            age_buckets["<30d"] += 1
        elif age <= 90:
            age_buckets["30-90d"] += 1
        else:
            age_buckets[">90d"] += 1
        if meta.get("superseded_by"):
            superseded_by += 1
        if c == "high" and age is not None:
            name = (meta.get("name") or fm.get("name") or os.path.splitext(os.path.basename(p))[0])
            high_conf_aged.append((age, name, lv or ""))
    high_conf_aged.sort(key=lambda x: -x[0])
    adoption = (canonical / total) if total else 0.0
    return {
        "total": total,
        "canonical": canonical,
        "flat": flat,
        "no_frontmatter": nofm,
        "adoption": adoption,
        "type_distribution": dict(types),
        "confidence_distribution": dict(confs),
        "last_verified_age": age_buckets,
        "superseded_by": superseded_by,
        # Watchlist floor: only high-confidence memories aged >=30d. Below that a
        # memory is freshly verified, not "staling" — flagging a 0d-old file as
        # fastest-staling is noise that erodes trust in the Improve step.
        "fastest_staling": [{"age_days": a, "name": n, "last_verified": l}
                            for a, n, l in high_conf_aged if a >= 30][:5],
    }


def collect_hooks() -> dict:
    """Per memory hook: run count, error rate, mean duration_s."""
    runs: Counter = Counter()
    errors: Counter = Counter()
    durations: dict[str, list[float]] = defaultdict(list)
    for src in ("hooks.jsonl", "hooks.jsonl.1", "hooks.jsonl.2"):
        for d in read_jsonl(f"{LOGS}/{src}"):
            h = d.get("hook")
            if h not in MEMORY_HOOKS:
                continue
            runs[h] += 1
            if d.get("outcome") in ("error", "fail"):
                errors[h] += 1
            dur = _duration_s(d)
            if dur is not None:
                durations[h].append(dur)
    out: dict = {}
    for h in MEMORY_HOOKS:
        n = runs.get(h, 0)
        err = errors.get(h, 0)
        ds = durations.get(h, [])
        out[h] = {
            "runs": n,
            "errors": err,
            "error_rate": (err / n) if n else 0.0,
            "mean_duration_s": (sum(ds) / len(ds)) if ds else None,
        }
    return out


# ── Issue list + verdict (depends on all collectors) ───────────────────
def collect_issues(capture, approval, invalidations, utilization, corpus, hooks) -> tuple[dict, list[str]]:
    """Build the issue-list rollup and the verdict flag set."""
    flags: list[str] = []

    # Never-consulted > 60d (only computable when consulted.json exists).
    never_60d: list[str] = []
    if utilization.get("available"):
        now = time.time()
        # Re-walk the corpus to get last_verified age per file, intersect with never-consulted.
        never_set = set(utilization.get("never_consulted_basenames", []))
        for p in _corpus_files(DEFAULT_MEMORY_DIR):
            name = os.path.basename(p)
            if name not in never_set:
                continue
            try:
                txt = open(p).read()
            except Exception:
                continue
            fm, _ = parse_frontmatter(txt)
            meta = fm.get("metadata", {}) if isinstance(fm.get("metadata"), dict) else {}
            lv = meta.get("last_verified") or fm.get("last_verified") or ""
            age = _days_since(lv, now)
            if age is not None and age > 60:
                never_60d.append(f"{name} (last_verified {lv}, {age}d)")
        # never-consulted > 50% flag
        if corpus.get("total") and utilization.get("never_consulted_pct", 0) > NEVER_CONSULTED_FLAG:
            flags.append(
                f"never-consulted {utilization['never_consulted_pct']*100:.0f}% "
                f"> {NEVER_CONSULTED_FLAG*100:.0f}%"
            )

    # Fastest-staling comes straight from the corpus collector.
    fastest = corpus.get("fastest_staling", [])

    # Zero-yield infer sessions count.
    zero_yield = capture.get("zero_yield_runs", 0)

    # Schema adoption %.
    adoption_pct = (corpus.get("adoption", 0) or 0) * 100
    if corpus.get("total") and (corpus.get("adoption", 0) or 0) < ADOPTION_FLAG:
        flags.append(f"canonical adoption {adoption_pct:.0f}% < {ADOPTION_FLAG*100:.0f}%")

    # Hook error rate flag.
    for h, info in hooks.items():
        if info["runs"] and info["error_rate"] > HOOK_ERROR_RATE_FLAG:
            flags.append(f"hook {h} error rate {info['error_rate']*100:.0f}% > {HOOK_ERROR_RATE_FLAG*100:.0f}%")

    issues = {
        "never_consulted_60d": never_60d,
        "fastest_staling": fastest,
        "zero_yield_infer_sessions": zero_yield,
        "schema_adoption_pct": round(adoption_pct, 1),
    }
    return issues, flags


def build_report(memory_dir: str) -> dict:
    capture = collect_capture()
    approval = collect_approval()
    invalidations = collect_invalidations()
    corpus_paths = _corpus_files(memory_dir)
    utilization = collect_utilization(corpus_paths)
    corpus = collect_corpus(memory_dir)
    hooks = collect_hooks()
    issues, flags = collect_issues(capture, approval, invalidations, utilization, corpus, hooks)
    verdict = {
        "status": "HEALTHY" if not flags else "NEEDS ATTENTION",
        "flags": flags,
    }
    return {
        "capture": capture,
        "approval": approval,
        "invalidations": invalidations,
        "utilization": utilization,
        "corpus": corpus,
        "hooks": hooks,
        "issues": issues,
        "verdict": verdict,
    }


# ── Renderers ──────────────────────────────────────────────────────────
def _rate_str(rate) -> str:
    return "n/a" if rate is None else f"{rate*100:.0f}%"


def print_text(report: dict) -> None:
    cap = report["capture"]
    appr = report["approval"]
    inv = report["invalidations"]
    util = report["utilization"]
    corp = report["corpus"]
    hooks = report["hooks"]
    issues = report["issues"]
    verdict = report["verdict"]

    print("# Memory Health\n")

    # ── Capture ──
    print("## Capture")
    dist = cap["yield_distribution"]
    print(f"  memory-infer runs: {cap['runs']}")
    print(f"  total candidates yielded: {cap['total_candidates']}")
    print(f"  yield distribution: 0→{dist[0]}  1→{dist[1]}  2→{dist[2]}  3+→{dist['3+']}")
    if cap["runs"] == 0:
        print("  (no memory-infer runs yet)")

    # ── Approval rate ──
    print("\n## Approval rate")
    if appr["resolved"] == 0:
        print(f"  (no resolves yet — {appr['pending']} pending)")
    else:
        print(f"  applied={appr['applied']}  dismissed={appr['dismissed']}  "
              f"rate={_rate_str(appr['rate'])}  pending={appr['pending']}")

    # ── Invalidations ──
    print("\n## Invalidations")
    if inv["total"] == 0:
        print("  (none queued)")
    else:
        print(f"  total={inv['total']}  stale-90d={inv['stale_90d']}  "
              f"overlap={inv['overlap']}  pending={inv['pending']}")

    # ── Utilization ──
    print("\n## Utilization")
    if not util.get("available"):
        print("  (no data yet — read hook not yet active)")
    else:
        pct = util["never_consulted_pct"] * 100
        print(f"  corpus={util['corpus_total']}  consulted={util['consulted']}  "
              f"never={util['never_consulted']} ({pct:.0f}%)  last_30d={util['consulted_30d']}")
        top = util.get("top5", [])
        if top:
            print("  top-5 consulted:")
            for t in top:
                print(f"    {t['count']:>3}×  {t['last_seen']}  {t['relpath']}")

    # ── Corpus shape ──
    print("\n## Corpus shape")
    print(f"  total={corp['total']}  canonical={corp['canonical']}  "
          f"flat={corp['flat']}  no-frontmatter={corp['no_frontmatter']}  "
          f"adoption={corp['adoption']*100:.0f}%")
    td = corp["type_distribution"]
    print(f"  type: " + "  ".join(f"{k}={v}" for k, v in sorted(td.items(), key=lambda x: -x[1])))
    cd = corp["confidence_distribution"]
    print(f"  confidence: " + "  ".join(f"{k}={v}" for k, v in sorted(cd.items(), key=lambda x: -x[1])))
    ab = corp["last_verified_age"]
    print(f"  last_verified age: none={ab['none']}  <30d={ab['<30d']}  "
          f"30-90d={ab['30-90d']}  >90d={ab['>90d']}")
    print(f"  superseded_by: {corp['superseded_by']}")

    # ── Hook health ──
    print("\n## Hook health")
    print(f"  {'hook':20} {'runs':>5} {'err':>4} {'err%':>5} {'mean_s':>7}")
    any_hooks = False
    for h in sorted(MEMORY_HOOKS):
        info = hooks.get(h, {})
        n = info.get("runs", 0)
        if n:
            any_hooks = True
        er = info.get("error_rate", 0) * 100
        ms = info.get("mean_duration_s")
        ms_s = f"{ms:.3f}" if ms is not None else "-"
        print(f"  {h:20} {n:>5} {info.get('errors',0):>4} {er:>4.0f}% {ms_s:>7}")
    if not any_hooks:
        print("  (no memory hook events yet)")

    # ── Issues ──
    print("\n## Issues")
    print(f"  schema adoption: {issues['schema_adoption_pct']:.0f}% canonical")
    print(f"  zero-yield infer sessions: {issues['zero_yield_infer_sessions']}")
    if util.get("available"):
        nv = issues["never_consulted_60d"]
        print(f"  never-consulted >60d: {len(nv)}")
        for n in nv[:8]:
            print(f"    - {n}")
        if len(nv) > 8:
            print(f"    ... ({len(nv)-8} more)")
    else:
        print("  never-consulted >60d: (no consulted data)")
    fs = issues["fastest_staling"]
    print(f"  fastest-staling (high-confidence, top 5):")
    if fs:
        for f in fs:
            print(f"    - {f['age_days']}d  {f['name']}  (last_verified {f['last_verified'] or '?'})")
    else:
        print("    (none — no high-confidence memory with a last_verified date)")

    # ── Verdict ──
    print("\n## Verdict")
    if verdict["status"] == "HEALTHY":
        print("  memory: HEALTHY")
    else:
        print(f"  memory: NEEDS ATTENTION ({len(verdict['flags'])} flags)")
        for f in verdict["flags"]:
            print(f"    ⚠ {f}")


def print_json(report: dict) -> None:
    print(json.dumps(report, indent=2, sort_keys=False))


# ── Entry point ────────────────────────────────────────────────────────
def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Memory corpus quality rollup (read-only).")
    ap.add_argument("--json", action="store_true", help="emit one JSON object instead of text")
    ap.add_argument("--memory-dir", default=DEFAULT_MEMORY_DIR,
                    help=f"memory corpus dir (default: {DEFAULT_MEMORY_DIR})")
    args = ap.parse_args(argv)

    if not os.path.isdir(args.memory_dir):
        # Degrade gracefully — empty corpus, missing sources. Still emit a report.
        print(f"warning: memory dir not found: {args.memory_dir}", file=sys.stderr)
    try:
        report = build_report(args.memory_dir)
    except Exception as e:
        # Never crash the slash command on a happy path; surface to stderr.
        print(f"error: failed to build report: {e}", file=sys.stderr)
        return 1
    if args.json:
        print_json(report)
    else:
        print_text(report)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
