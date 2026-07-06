#!/usr/bin/env python3
"""memory_review.py — propose harness tweaks from /memory health findings.

Advisory + deterministic. Shells `memory_health.py --json`, maps findings to
numbered proposed tweaks (finding → why → action), prints an accept/defer list.
No auto-application — accepting a tweak means making it a follow-up task.

Never exits non-zero on the happy path; errors go to stderr (caller is a slash
command and is not blocked).

Usage: memory_review.py
"""
import json
import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
HEALTH = os.path.join(SCRIPT_DIR, "memory_health.py")


def run_health():
    try:
        out = subprocess.run(
            [sys.executable, HEALTH, "--json"],
            capture_output=True, text=True, timeout=10,
        )
    except Exception as e:
        sys.stderr.write("error: could not run memory_health.py: %s\n" % e)
        sys.exit(0)
    if out.returncode != 0 or not out.stdout.strip():
        sys.stderr.write("error: memory_health.py failed\n")
        sys.exit(0)
    return json.loads(out.stdout)


def tweaks(d):
    """Return [(category, finding, why, action), ...] from health data."""
    issues = d.get("issues", {}) or {}
    verdict = d.get("verdict", {}) or {}
    util = d.get("utilization", {}) or {}
    cap = d.get("capture", {}) or {}
    appr = d.get("approval", {}) or {}
    hooks = d.get("hooks", {}) or {}
    corpus = d.get("corpus", {}) or {}
    props = []

    # 1. Schema adoption — the foundation for staleness/overlap machinery.
    adopt = issues.get("schema_adoption_pct")
    if adopt is not None and adopt < 10:
        props.append((
            "adoption",
            "Canonical-schema adoption is %.0f%% (%d/%d files)." % (
                adopt, corpus.get("canonical", 0), corpus.get("total", 0)),
            "Staleness/overlap machinery has almost nothing to chew on; ~80% of "
            "the corpus is invisible to it (no confidence/last_verified).",
            "Run the deferred S3 migration — backfill high-value files onto the "
            "canonical schema. Safe-archive the ~19 pure-noise files first.",
        ))

    # 2. Utilization — unread memories are dead weight.
    pct = util.get("never_consulted_pct")
    if pct is not None and pct > 0.5 and util.get("available"):
        props.append((
            "utilization",
            "%.0f%% of corpus (%d files) never consulted." % (
                pct * 100, util.get("never_consulted", 0)),
            "Unread memories are either low-value (archive) or recall isn't "
            "surfacing them at the right moment.",
            "Sample never_consulted_basenames from the health report; archive cruft, "
            "and reconsider whether the live ones should be seeded into warm-start.",
        ))

    # 3. Zero-yield infer sessions — cost-thesis lever.
    zy = issues.get("zero_yield_infer_sessions", 0)
    runs = cap.get("runs", 0)
    if zy and zy >= 2 and runs and zy / runs >= 0.2:
        props.append((
            "capture-cost",
            "%d/%d infer sessions yielded 0 candidates." % (zy, runs),
            "Paying glm-4.7 every session-end for >25% empty runs — likely "
            "prompt/threshold noise on short or ephemeral sessions.",
            "Raise the user-turn threshold (12→16) or tighten the dialectic "
            "prompt's 'durable+novel' bar; re-check approval rate after.",
        ))

    # 4. Approval rate — precision signal (only meaningful once resolves exist).
    rate = appr.get("rate")
    resolved = appr.get("resolved", 0)
    if rate is not None and resolved >= 3 and rate < 0.4:
        props.append((
            "precision",
            "Approval rate is %.0f%% over %d resolved candidates." % (
                rate * 100, resolved),
            "Low precision = infer is producing candidates the user dismisses.",
            "Tighten the prompt; consider down-weighting low-confidence candidates "
            "or skipping them entirely.",
        ))

    # 5. Hook errors — silent rot if ignored.
    for h, m in hooks.items():
        er = m.get("error_rate", 0) or 0
        if er > 0.1:
            props.append((
                "hook-health",
                "%s error rate %.0f%% (%d/%d)." % (
                    h, er * 100, m.get("errors", 0), m.get("runs", 0)),
                "A memory hook is failing — non-blocking, so it rots silently.",
                "Inspect ~/vault/logs/hooks.jsonl and the hook's own log for %s." % h,
            ))

    # 6. Staleness — re-verify / supersede candidates.
    fs = issues.get("fastest_staling", []) or []
    if fs:
        props.append((
            "staleness",
            "%d high-confidence memor%s going stale." % (
                len(fs), "y" if len(fs) == 1 else "ies"),
            "Stale high-confidence facts risk the 'textiles' bug class "
            "(confidently wrong, never re-checked).",
            "Re-verify or supersede via /reflect memory.",
        ))
    nc60 = issues.get("never_consulted_60d", []) or []
    if nc60:
        props.append((
            "staleness",
            "%d memor%s not consulted in >60d." % (
                len(nc60), "y" if len(nc60) == 1 else "ies"),
            "Long-unconsulted = likely stale or low-value.",
            "Re-verify; archive if still unused after one more cycle.",
        ))

    return props


def main():
    d = run_health()
    props = tweaks(d)
    verdict = d.get("verdict", {}) or {}
    status = verdict.get("status", "?")
    flags = verdict.get("flags", []) or []

    print("# Memory Review — proposed harness tweaks\n")
    print("Verdict: %s (%d flag%s)\n" % (status, len(flags), "" if len(flags) == 1 else "s"))

    if not props:
        print("No actionable findings — the memory loop looks healthy.")
        print("(Empty sections in the health report are normal early on.)\n")
        return

    print("%d proposed tweak%s. Advisory — accept/defer per item, then act:\n" % (
        len(props), "" if len(props) == 1 else "s"))
    for i, (cat, finding, why, action) in enumerate(props, 1):
        print("[%d] (%s) %s" % (i, cat, finding))
        print("    why:    %s" % why)
        print("    action: %s\n" % action)
    print("Accept a tweak → make it a follow-up task. This command changes nothing.")


if __name__ == "__main__":
    main()
