#!/usr/bin/env python3
"""discrepancy-scan.py — cheap candidate-finder for SEMANTIC discrepancies.

The middle tier between vault-audit (mechanical) and the librarian (semantic judge).
It cannot decide what's true — it surfaces *suspects* so the librarian's expensive
reading is bounded instead of O(n^2) over the whole vault. Every finding is a
CANDIDATE; expect false positives — the librarian adjudicates against dates + sources.

Checks:
  1. metric drift        — same metric cited with different numbers across docs
  2. decision statements — decision/status/supersede language to verify is consistent
  3. note↔transcript     — numbers/proper-nouns in a recording's transcript that never
                           made it into that day's meeting notes (dropped/rewritten detail)
  4. entity co-mentions  — docs touching the same entity, to read together for conflicts

Scope defaults to the last 7 days (the weekly sweep), but metric comparison pulls ALL
docs mentioning a metric that changed this week, so drift against old docs is caught.

Usage: discrepancy-scan.py [--since YYYY-MM-DD] [--full] [--out FILE]
Output: a markdown candidate report to stdout (and --out if given). Stdlib only.
"""

import os
import re
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

VAULT = Path(os.path.expanduser("~/Documents/vault-work"))
NOTES = VAULT / "Notes"
DAILY = VAULT / "Daily"
GLOSS = VAULT / "Glossary"
PEOPLE = VAULT / "People"

SKIP_DIRS = {"templates", "archive", "archived", ".obsidian", "node_modules", ".git"}


def arg(name, default=None):
    if name in sys.argv:
        i = sys.argv.index(name)
        return sys.argv[i + 1] if i + 1 < len(sys.argv) else default
    return default


SINCE = arg("--since") or (datetime.now() - timedelta(days=7)).strftime("%Y-%m-%d")
FULL = "--full" in sys.argv
OUT = arg("--out")


def md_files(base):
    if not base.is_dir():
        return
    for p in base.rglob("*.md"):
        if any(part in SKIP_DIRS for part in p.parts):
            continue
        yield p


def read(p):
    try:
        return p.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return ""


def frontmatter_val(text, key):
    m = re.search(rf"(?m)^{key}:\s*(.+)$", text[:600])
    return m.group(1).strip().strip('"').strip("'") if m else ""


def changed_since(since):
    """Files changed since <since> per git (relevance filter for the week)."""
    try:
        out = subprocess.run(
            ["git", "-C", str(VAULT), "log", f"--since={since}", "--name-only",
             "--pretty=format:", "--", "Notes/**/*.md", "Daily/**/*.md"],
            capture_output=True, text=True, timeout=30,
        ).stdout
        return {VAULT / line.strip() for line in out.splitlines() if line.strip().endswith(".md")}
    except Exception:
        return set()


# ── entity / metric vocabulary ──────────────────────────────────────────

def load_terms(bases):
    """Return {term_lower: canonical_name} from the given bases (name + aliases)."""
    terms = {}
    NON_ENTITY = {"readme", "index", "claude", "_index", "template", "knowledge_base",
                  "project_log", "project_arc"}
    for base in bases:
        for p in md_files(base):
            canon = p.stem
            if len(canon) < 3 or canon.lower() in NON_ENTITY:
                continue
            terms[canon.lower()] = canon
            al = frontmatter_val(read(p), "aliases")
            if al:
                for a in re.split(r"[,\[\]]", al):
                    a = a.strip().strip('"').strip("'").lower()
                    if len(a) >= 3:
                        terms[a] = canon
    return terms


NUM_RE = re.compile(
    r"(₹\s?)?(\d[\d,]*(?:\.\d+)?)\s?(%|bps|crore|cr|lakhs?|lacs?|[KkLMmxX])?\b"
)
UNIT_MAP = {"crore": "cr", "cr": "cr", "lakh": "l", "lakhs": "l", "lac": "l",
            "lacs": "l", "l": "l", "k": "k", "m": "m", "x": "x", "%": "%",
            "bps": "bps", "": ""}

# A *value-shaped* number: has a unit suffix OR a ₹ prefix. Bare integers are
# excluded — they're list indices, IDs, years, ADR numbers (the noise source).
VALUE_RE = re.compile(
    r"(₹\s?\d[\d,]*(?:\.\d+)?(?:\s?(?:cr|crore|lakhs?|lacs?|[KkLM]))?"
    r"|\d[\d,]*(?:\.\d+)?\s?(?:%|bps|cr|crore|lakhs?|lacs?|[KkLMxX]))\b"
)
# Reference/catalog dumps are wall-to-wall numbers — never compare drift inside them.
CATALOG_SKIP = ("mixpanel-boards", "sheet-methodologies", "research_script_index",
                "schema-map", "board", "supporting_docs/", "-original-", "lexicon")


def is_catalog(relpath):
    low = relpath.lower()
    return any(s in low for s in CATALOG_SKIP)


def norm_num(numstr, unit):
    v = numstr.replace(",", "")
    try:
        f = float(v)
    except ValueError:
        return None
    u = UNIT_MAP.get((unit or "").lower(), (unit or "").lower())
    fs = f"{f:.4g}"
    return f"{fs}{u}"


def norm_value(s):
    """Normalize a VALUE_RE match string (with unit/₹) to a comparable token."""
    s = s.strip()
    cur = s.startswith("₹")
    m = re.search(r"(\d[\d,]*(?:\.\d+)?)\s?([a-zA-Z%]*)", s)
    if not m:
        return None
    nv = norm_num(m.group(1), m.group(2))
    if not nv:
        return None
    if re.fullmatch(r"(19|20)\d\d", m.group(1)):   # drop years
        return None
    return ("₹" if cur else "") + nv


def sentence_around(text, idx, width=120):
    a = text.rfind(".", max(0, idx - width), idx) + 1
    b = text.find(".", idx)
    b = idx + width if b < 0 else min(b + 1, idx + width)
    return re.sub(r"\s+", " ", text[max(a, idx - width):b]).strip()


# ── checks ──────────────────────────────────────────────────────────────

def check_metric_drift(docs, changed, metric_terms):
    """Same metric → different *value-shaped* number, in a tight window, across docs.

    High precision by construction: requires a unit/₹ (no bare integers) within 22
    chars of the metric mention, and skips catalog/dump docs. Better to miss a drift
    than to flood the librarian with list-index noise.
    """
    seen = defaultdict(lambda: defaultdict(list))   # metric -> value -> [(file,sent,upd)]
    changed_metrics = set()
    for p, text in docs.items():
        rp = rel(p)
        if is_catalog(rp):
            continue
        low = text.lower()
        updated = frontmatter_val(text, "updated")
        for term, canon in metric_terms.items():
            start = 0
            while True:
                i = low.find(term, start)
                if i < 0:
                    break
                end = i + len(term)
                start = end
                # tight window on either side of the metric mention
                after = text[end: end + 22]
                before = text[max(0, i - 22): i]
                m = VALUE_RE.search(after) or VALUE_RE.search(before)
                if not m:
                    continue
                nv = norm_value(m.group(0))
                if not nv:
                    continue
                seen[canon][nv].append((rp, sentence_around(text, i), updated))
                if p in changed:
                    changed_metrics.add(canon)
    # A real discrepancy = the SAME metric carries two *propagated* facts (each
    # asserted in >=2 distinct docs) that disagree. One-off contextual numbers
    # (a milestone here, a target there) are filtered out — they're not conflicts.
    out = []
    for metric in sorted(changed_metrics):
        propagated = {}
        for v, refs in seen[metric].items():
            files = sorted({r[0] for r in refs})
            if len(files) >= 2:
                # keep one example ref per distinct file
                ex = {}
                for f, s, u in refs:
                    ex.setdefault(f, (f, s, u))
                propagated[v] = list(ex.values())
        if len(propagated) >= 2:
            out.append((metric, propagated))
    return out


DECISION_RE = re.compile(
    r"\b(decided|we chose|chose to|rejected|going with|superseded?|deprecat|"
    r"no longer|instead of|changed to|moved to|switch(?:ed)? to|final decision|"
    r"agreed to|aligned on)\b", re.I)


def check_decisions(docs, changed):
    out = []
    for p in changed:
        text = docs.get(p, "")
        hits = []
        for m in DECISION_RE.finditer(text):
            hits.append(sentence_around(text, m.start()))
        if hits:
            out.append((rel(p), dedupe(hits)[:6]))
    return out


CAP_RE = re.compile(r"\b([A-Z][a-zA-Z0-9]{2,}(?:\s[A-Z][a-zA-Z0-9]{2,}){0,2}|[A-Z]{3,})\b")
STOP_CAPS = {"The", "This", "That", "There", "Then", "These", "Those", "With",
             "From", "What", "When", "Where", "Which", "Action", "Items", "Open",
             "Questions", "Review", "Summary", "Meeting", "Notes", "Date", "Key"}


def check_transcript_fidelity(changed, terms):
    """Value-shaped numbers + real proper nouns in a transcript absent from the note.

    Only value-shaped numbers (unit/₹/%) — drops whisperx timestamps. Only multi-word
    Capitalized phrases, ALLCAPS acronyms, or known entities — drops sentence-start
    fillers ("Okay", "Correct")."""
    out = []
    days = set()
    for p in changed:
        if DAILY in p.parents:
            days.add(p.parent)
    for tx in DAILY.rglob("*transcript*.txt"):
        days.add(tx.parent)
    for day in sorted(days):
        txts = sorted({*day.glob("*transcript*.txt"), *day.glob("recording_*.txt")})
        notes = list(day.glob("*.md"))
        if not txts or not notes:
            continue
        tx_text = " ".join(read(t) for t in txts)
        note_text = " ".join(read(n) for n in notes)
        if not tx_text.strip():
            continue
        note_low = note_text.lower()
        tx_vals = {norm_value(m.group(0)) for m in VALUE_RE.finditer(tx_text)}
        note_vals = {norm_value(m.group(0)) for m in VALUE_RE.finditer(note_text)}
        missing_nums = sorted(n for n in (tx_vals - note_vals) if n)[:15]
        # proper nouns: multi-word phrase, OR ALLCAPS>=3, OR a known entity term
        missing_caps = []
        for c in sorted({c for c in CAP_RE.findall(tx_text) if c not in STOP_CAPS}):
            if c.lower() in note_low:
                continue
            if (" " in c) or re.fullmatch(r"[A-Z0-9]{3,}", c) or c.lower() in terms:
                missing_caps.append(c)
        missing_caps = missing_caps[:15]
        if missing_nums or missing_caps:
            out.append((rel(day), [t.name for t in txts], missing_nums, missing_caps))
    return out


def check_co_mentions(docs, changed, terms):
    """Entities touched this week → the Notes/Daily docs mentioning them (read together).

    Glossary/People self-references are excluded — a glossary note naming its own term
    is not a discrepancy signal. Only content docs (where drift actually happens)."""
    canon_docs = defaultdict(set)
    changed_entities = set()
    for p, text in docs.items():
        if GLOSS in p.parents or PEOPLE in p.parents:
            continue
        low = text.lower()
        for term, canon in terms.items():
            if re.search(r"\b" + re.escape(term) + r"\b", low):
                canon_docs[canon].add(rel(p))
                if p in changed:
                    changed_entities.add(canon)
    # Only FOCUSED sets are actionable: an entity in 2-8 docs can be "read together"
    # for a conflict; one in 40 docs is just a core concept, not a candidate.
    out = []
    for e in sorted(changed_entities):
        d = canon_docs[e]
        if 2 <= len(d) <= 8:
            out.append((e, sorted(d)))
    return out


# ── helpers ─────────────────────────────────────────────────────────────

def rel(p):
    try:
        return str(Path(p).relative_to(VAULT))
    except ValueError:
        return str(p)


def dedupe(seq):
    seen, out = set(), []
    for s in seq:
        if s not in seen:
            seen.add(s)
            out.append(s)
    return out


def main():
    terms = load_terms([GLOSS, PEOPLE])                       # all, for co-mentions
    metric_terms = load_terms([GLOSS / "metrics", GLOSS / "products"])  # for drift
    changed = changed_since(SINCE)
    docs = {}
    for base in (NOTES, DAILY, GLOSS, PEOPLE):
        for p in md_files(base):
            docs[p] = read(p)
    scope = "ALL docs" if FULL else f"changed since {SINCE} ({len(changed)} files)"

    L = []
    L.append(f"# Discrepancy candidates — {datetime.now():%Y-%m-%d}")
    L.append(f"\n_Scope: {scope}. These are SUSPECTS, not verdicts — adjudicate against "
             f"dates + sources (transcript = ground truth)._\n")

    drift = check_metric_drift(docs, changed if not FULL else set(docs), metric_terms)
    L.append("## 1. Metric / number drift  (same metric, different values)")
    if drift:
        for metric, vals in drift[:25]:
            L.append(f"\n### {metric} — {len(vals)} distinct values")
            for nv, refs in sorted(vals.items(), key=lambda x: -len(x[1])):
                files = ", ".join(f"`{f}`" + (f" (upd {u})" if u else "")
                                  for f, _s, u in refs[:4])
                L.append(f"- **{nv}** — {files}")
                L.append(f"    - e.g. \"{refs[0][1][:150]}\"")
    else:
        L.append("- (none)")

    decisions = check_decisions(docs, changed)
    L.append("\n## 2. Decision / status statements  (verify consistent with log+ADR+KB)")
    if decisions:
        for f, hits in decisions[:20]:
            L.append(f"\n- `{f}`")
            for h in hits:
                L.append(f"    - \"{h[:160]}\"")
    else:
        L.append("- (none in range)")

    fid = check_transcript_fidelity(changed, terms)
    L.append("\n## 3. Note ↔ recording fidelity  (in transcript, missing from the note)")
    if fid:
        for day, txts, nums, caps in fid[:20]:
            L.append(f"\n- `{day}` (transcripts: {', '.join(txts)})")
            if nums:
                L.append(f"    - numbers not in notes: {', '.join(nums)}")
            if caps:
                L.append(f"    - terms/names not in notes: {', '.join(caps)}")
    else:
        L.append("- (no transcript/note pairs in range)")

    co = check_co_mentions(docs, changed, terms)
    L.append("\n## 4. Entity co-mentions  (read these together for conflicts)")
    if co:
        for e, ds in co[:20]:
            L.append(f"- **{e}** → {', '.join(f'`{d}`' for d in ds[:8])}"
                     + (f" +{len(ds)-8} more" if len(ds) > 8 else ""))
    else:
        L.append("- (none)")

    report = "\n".join(L) + "\n"
    sys.stdout.write(report)
    if OUT:
        Path(OUT).write_text(report, encoding="utf-8")
        sys.stderr.write(f"\n[written to {OUT}]\n")


if __name__ == "__main__":
    main()
