#!/usr/bin/env python3
"""
Export Clean Markdown — strips Obsidian/vault internals for external sharing.

Usage:
    python export_clean_md.py <input.md> [--output <path>] [--strip-sections "Foo,Bar"]

Defaults to writing into <vault>/exports/<filename>.
"""

import re
import sys
import argparse
from pathlib import Path
from typing import Optional, List

# ── Sections to remove entirely (matched against heading text, ignoring leading "13. " numbering) ──

DEFAULT_INTERNAL_SECTIONS = [
    "Sources (Knowledge Docs)",
    "Related Specs",
]

# ── Line-level patterns to remove ──

INTERNAL_LINE_PATTERNS = [
    r"^\s*Script:\s*`?Notes/",            # Script file references
    r"^\s*See\s+\[\[.+?\]\]",             # "See [[internal-link]] …" navigation lines
    r"^\s*Full analysis:\s*\[\[",          # "Full analysis: [[doc]]"
]


def strip_frontmatter(text: str) -> str:
    """Remove YAML frontmatter delimited by ---."""
    if text.startswith("---"):
        end = text.find("---", 3)
        if end != -1:
            return text[end + 3:].lstrip("\n")
    return text


def convert_wikilinks(text: str) -> str:
    """[[Page|Alias]] -> Alias, [[Page]] -> Page."""
    text = re.sub(r"\[\[([^\]|]+)\|([^\]]+)\]\]", r"\2", text)
    text = re.sub(r"\[\[([^\]]+)\]\]", r"\1", text)
    return text


def strip_internal_sections(text: str, section_names: List[str]) -> str:
    """Remove whole sections (heading + body) whose title matches the list."""
    lower_names = [n.lower() for n in section_names]
    lines = text.split("\n")
    result = []
    skip_level = None          # heading level we are currently skipping

    for line in lines:
        m = re.match(r"^(#{1,6})\s+(.+)", line)
        if m:
            level = len(m.group(1))
            heading = re.sub(r"^\d+\.\s*", "", m.group(2)).strip()

            if skip_level is not None:
                if level <= skip_level:
                    skip_level = None       # reached same-or-higher heading → stop skipping
                else:
                    continue                # sub-heading inside skipped section

            for name in lower_names:
                if name in heading.lower():
                    skip_level = level
                    break

            if skip_level is not None:
                continue                    # skip the heading line itself

        elif skip_level is not None:
            continue

        result.append(line)

    return "\n".join(result)


def strip_internal_lines(text: str) -> str:
    """Drop individual lines matching internal patterns."""
    lines = text.split("\n")
    result = []
    for line in lines:
        if any(re.search(p, line) for p in INTERNAL_LINE_PATTERNS):
            continue
        result.append(line)
    return "\n".join(result)


def strip_marked_blocks(text: str) -> str:
    """Remove content between <!-- export:strip --> and <!-- export:end --> markers."""
    return re.sub(
        r"<!--\s*export:strip\s*-->.*?<!--\s*export:end\s*-->",
        "",
        text,
        flags=re.DOTALL,
    )


def clean_blockquote_citations(text: str) -> str:
    """Simplify blockquotes that exist only to cite internal docs.

    > **Research basis:** [[doc-name]] — actual insight here
    becomes:
    > **Research basis:** actual insight here
    """
    # Pattern: > **Label:** [[link]] — rest
    text = re.sub(
        r"^(>\s*\*\*[^*]+\*\*:?\s*)\[\[[^\]]+\]\]\s*—\s*",
        r"\1",
        text,
        flags=re.MULTILINE,
    )
    # Pattern: > **Label:** [[link]] (rest of text)
    text = re.sub(
        r"^(>\s*\*\*[^*]+\*\*:?\s*)\[\[[^\]]+\]\]\s+",
        r"\1",
        text,
        flags=re.MULTILINE,
    )
    return text


def collapse_blank_lines(text: str) -> str:
    """3+ consecutive blank lines -> 2."""
    return re.sub(r"\n{3,}", "\n\n", text)


def export_clean(input_path: str, output_path: Optional[str] = None,
                 extra_sections: Optional[List[str]] = None) -> str:
    """Run the full cleaning pipeline and write the result."""
    src = Path(input_path)
    if not src.exists():
        raise FileNotFoundError(f"Not found: {input_path}")

    content = src.read_text(encoding="utf-8")

    sections = DEFAULT_INTERNAL_SECTIONS + (extra_sections or [])

    # Pipeline — order matters
    content = strip_frontmatter(content)
    content = strip_marked_blocks(content)
    content = strip_internal_sections(content, sections)
    content = strip_internal_lines(content)
    content = clean_blockquote_citations(content)
    content = convert_wikilinks(content)
    content = collapse_blank_lines(content)
    content = content.strip() + "\n"

    # Output path
    if output_path:
        dst = Path(output_path)
    else:
        vault = Path(__file__).resolve().parent.parent.parent   # System/scripts → vault root
        exports = vault / "exports"
        exports.mkdir(exist_ok=True)
        dst = exports / src.name

    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(content, encoding="utf-8")
    return str(dst)


# ── CLI ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Export clean markdown for external sharing")
    parser.add_argument("input", help="Input markdown file path")
    parser.add_argument("--output", "-o", help="Output path (default: exports/<filename>)")
    parser.add_argument("--strip-sections", help="Comma-separated extra section headings to strip")
    args = parser.parse_args()

    extra = [s.strip() for s in args.strip_sections.split(",")] if args.strip_sections else None
    result = export_clean(args.input, args.output, extra)
    print(f"Exported → {result}")
