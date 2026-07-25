#!/usr/bin/env python3
"""Deterministic writer for the per-project RESUME board (System/handoffs/RESUME.md).

The board is the L0 continuity artifact: one `## <project>` section per active
thread, current-state only (history lives in each Notes/<project>/PROJECT_LOG.md).
vault-push calls this at every session end instead of hand-editing the file — that
keeps the "overwrite only the touched section, never clobber the others" invariant
mechanical rather than relying on the model getting string-surgery right on a
growing file.

What one `update` does, atomically:
  1. Replace (or insert) the target project's `## <project>` section.
  2. Move it to the top of the active sections (newest-touched first).
  3. Bump frontmatter `last_touched` + `updated`.
  4. Sweep active sections whose `_updated:` date is older than --archive-after-days
     into a collapsed `## Archived` block (kept for reference, not deleted). A project
     that is touched again is pulled back out of Archived automatically.
  Every other section is preserved byte-for-byte.

Usage:
  python tools/resume_board.py update --project referral-program \
      --in-flight "..." --next "..." --blockers "..." --resume-with "..." \
      [--session slug] [--updated "YYYY-MM-DD HH:MM"] \
      [--archive-after-days 30] [--no-archive] [--file PATH]

  python tools/resume_board.py archive [--archive-after-days 30] [--file PATH]
      # run the dormancy sweep without updating a section

stdlib only; Python 3.9+.
"""
import argparse
import datetime as _dt
import os
import re
import sys

DEFAULT_FILE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "System", "handoffs", "RESUME.md",
)
ARCHIVED_NAME_PREFIX = "Archived"
_DATE_RE = re.compile(r"(\d{4}-\d{2}-\d{2})")


def _now_stamp():
    return _dt.datetime.now().strftime("%Y-%m-%d %H:%M")


def _split_frontmatter(text):
    """Return (frontmatter_lines, body_text). frontmatter excludes the --- fences."""
    if not text.startswith("---"):
        return [], text
    end = text.find("\n---", 3)
    if end == -1:
        return [], text
    fm = text[3:end].strip("\n").split("\n")
    rest = text[end + len("\n---"):]
    if rest.startswith("\n"):
        rest = rest[1:]
    return fm, rest


def _parse_sections(body):
    """Split body into (preamble, sections) where sections is a list of
    {name, lines}. A section starts at a column-0 '## ' header. The preamble is
    everything before the first such header (H1, intro blockquote, template comment)."""
    lines = body.split("\n")
    preamble = []
    sections = []
    cur = None
    for ln in lines:
        if ln.startswith("## "):
            if cur is not None:
                sections.append(cur)
            cur = {"name": ln[3:].strip(), "lines": [ln]}
        elif cur is None:
            preamble.append(ln)
        else:
            cur["lines"].append(ln)
    if cur is not None:
        sections.append(cur)
    return preamble, sections


def _section_date(sec):
    """The date on a section's `_updated:` line, as 'YYYY-MM-DD', or None."""
    for ln in sec["lines"]:
        if ln.strip().startswith("_updated:"):
            m = _DATE_RE.search(ln)
            if m:
                return m.group(1)
    return None


def _split_active_archived(sections):
    """Partition sections at the '## Archived' divider. Returns (active, archived);
    the divider section itself is dropped (regenerated on serialize)."""
    for i, s in enumerate(sections):
        if s["name"].startswith(ARCHIVED_NAME_PREFIX):
            return sections[:i], sections[i + 1:]
    return list(sections), []


def _build_section(project, args, stamp):
    sess = (" · session: %s" % args.session) if args.session else ""
    body = [
        "## %s" % project,
        "_updated: %s%s_" % (stamp, sess),
        "- **In-flight:** %s" % (args.in_flight or "—"),
        "- **Next:** %s" % (args.next or "—"),
        "- **Blockers:** %s" % (args.blockers or "none"),
        "- **Resume with:** %s" % (args.resume_with or "N/A — clean stop"),
    ]
    return {"name": project, "lines": body}


def _set_fm(fm, key, value):
    pat = re.compile(r"^%s\s*:" % re.escape(key))
    for i, ln in enumerate(fm):
        if pat.match(ln):
            fm[i] = "%s: %s" % (key, value)
            return
    fm.append("%s: %s" % (key, value))


def _serialize(fm, preamble, active, archived, archive_after_days):
    out = []
    out.append("---")
    out.extend(fm)
    out.append("---")
    pre = "\n".join(preamble).rstrip("\n")
    if pre:
        out.append(pre)
    out.append("")
    for sec in active:
        out.append("\n".join(l.rstrip() for l in sec["lines"]).rstrip("\n"))
        out.append("")
    if archived:
        out.append("## Archived (dormant >%dd · kept for reference)" % archive_after_days)
        out.append("_Touch a project again and `update` pulls it back to the top._")
        out.append("")
        for sec in archived:
            out.append("\n".join(l.rstrip() for l in sec["lines"]).rstrip("\n"))
            out.append("")
    text = "\n".join(out).rstrip("\n") + "\n"
    return text


def _load(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def cmd_update(args):
    text = _load(args.file)
    fm, body = _split_frontmatter(text)
    preamble, sections = _parse_sections(body)
    active, archived = _split_active_archived(sections)

    stamp = args.updated or _now_stamp()
    # Drop any existing section for this project, wherever it lives.
    active = [s for s in active if s["name"] != args.project]
    archived = [s for s in archived if s["name"] != args.project]
    # Insert fresh section at the top of active.
    active.insert(0, _build_section(args.project, args, stamp))

    if not args.no_archive:
        active, archived = _sweep(active, archived, args.archive_after_days, keep=args.project)

    _set_fm(fm, "last_touched", args.project)
    _set_fm(fm, "updated", stamp)

    out = _serialize(fm, preamble, active, archived, args.archive_after_days)
    _write(args.file, out)
    print("updated section '%s'; active=%d archived=%d" % (args.project, len(active), len(archived)))


def cmd_archive(args):
    text = _load(args.file)
    fm, body = _split_frontmatter(text)
    preamble, sections = _parse_sections(body)
    active, archived = _split_active_archived(sections)
    active, archived = _sweep(active, archived, args.archive_after_days, keep=None)
    out = _serialize(fm, preamble, active, archived, args.archive_after_days)
    _write(args.file, out)
    print("archive sweep: active=%d archived=%d" % (len(active), len(archived)))


def _sweep(active, archived, days, keep):
    """Move active sections older than `days` into archived. `keep` is never archived."""
    cutoff = (_dt.date.today() - _dt.timedelta(days=days)).isoformat()
    still_active, newly = [], []
    for s in active:
        d = _section_date(s)
        if s["name"] != keep and d is not None and d < cutoff:
            newly.append(s)
        else:
            still_active.append(s)
    # newly-archived go on top of the archived list (most-recently-dormant first)
    return still_active, newly + archived


def _write(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, path)


def main(argv=None):
    p = argparse.ArgumentParser(description="Deterministic RESUME board writer.")
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--file", default=DEFAULT_FILE, help="path to RESUME.md")
    common.add_argument("--archive-after-days", type=int, default=30)
    sub = p.add_subparsers(dest="cmd")

    up = sub.add_parser("update", parents=[common], help="replace/insert a project's section")
    up.add_argument("--project", required=True)
    up.add_argument("--in-flight", default="")
    up.add_argument("--next", default="")
    up.add_argument("--blockers", default="")
    up.add_argument("--resume-with", default="")
    up.add_argument("--session", default="")
    up.add_argument("--updated", default="", help="override timestamp (default: now)")
    up.add_argument("--no-archive", action="store_true", help="skip the dormancy sweep")

    sub.add_parser("archive", parents=[common], help="run the dormancy sweep only")

    args = p.parse_args(argv)
    if args.cmd == "update":
        cmd_update(args)
    elif args.cmd == "archive":
        cmd_archive(args)
    else:
        p.print_help()
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
