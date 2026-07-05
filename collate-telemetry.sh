#!/usr/bin/env bash
# collate-telemetry.sh — MAINTAINER. Build the "same table": pull every *.summary.json that
# adopters have reported into the shared folder and fold them into ONE index CSV, then
# publish the CSV back into the folder. The per-report summaries are immutable and never
# overwritten; the CSV is regenerated from the full set each run, so the table only grows.
#
# Usage:  ./collate-telemetry.sh --folder <ID> [--remote gdrive] [--no-publish]
set -uo pipefail

REMOTE="gdrive"; FOLDER=""; PUBLISH=1
while [ $# -gt 0 ]; do
  case "$1" in
    --folder)     FOLDER="${2:?}"; shift ;;
    --remote)     REMOTE="${2:?}"; shift ;;
    --no-publish) PUBLISH=0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$FOLDER" ] || { echo "✗ --folder <ID> required" >&2; exit 1; }
command -v rclone >/dev/null 2>&1 || { echo "✗ rclone not installed." >&2; exit 1; }

DEST="${REMOTE},root_folder_id=${FOLDER}:"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/telemetry-collate.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

echo "Pulling *.summary.json from folder $FOLDER …"
rclone copy "$DEST" "$TMP" --include "*.summary.json" --contimeout 30s --timeout 120s -q \
  || { echo "✗ rclone pull failed (folder shared to you?)." >&2; exit 1; }

N="$(find "$TMP" -name '*.summary.json' | wc -l | tr -d ' ')"
[ "$N" -gt 0 ] || { echo "No summary files yet — nothing to collate." ; exit 0; }

OUT="$TMP/telemetry-index.csv"
COLS="collected_at_utc,operator,install_id,machine_tag,harness_version,harness_committed,os,hook_rows,exit_nonzero,warm_start_degraded,outcome_errors,daily_job_failures,bundle_name"
python3 - "$TMP" "$OUT" "$COLS" <<'PY'
import sys, json, csv, glob, os
tmp, out, cols = sys.argv[1], sys.argv[2], sys.argv[3].split(",")
rows = []
for f in glob.glob(os.path.join(tmp, "*.summary.json")):
    try:
        d = json.load(open(f))
        rows.append([d.get(c, "") for c in cols])
    except Exception:
        continue
rows.sort(key=lambda r: r[0])  # by collected_at_utc
with open(out, "w", newline="") as fh:
    w = csv.writer(fh); w.writerow(cols); w.writerows(rows)
print(f"  {len(rows)} reports → {os.path.basename(out)}")
PY

echo "── index preview (latest 8) ──"
{ head -1 "$OUT"; tail -n +2 "$OUT" | tail -8; } | column -s, -t 2>/dev/null || cat "$OUT"

if [ "$PUBLISH" = "1" ]; then
  rclone copyto "$OUT" "${DEST}telemetry-index.csv" --contimeout 30s --timeout 60s -q \
    && echo "✓ published telemetry-index.csv into folder $FOLDER" \
    || echo "⚠ publish failed — CSV is at $OUT (kept)."
  [ "$PUBLISH" = 1 ] && trap - EXIT && echo "  local copy: $OUT"
fi
