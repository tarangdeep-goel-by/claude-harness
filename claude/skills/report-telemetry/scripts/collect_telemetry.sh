#!/usr/bin/env bash
# collect_telemetry.sh — bundle the harness's local telemetry logs and report them to a
# shared Google Drive folder, on demand OR on a schedule, using rclone (the reporter's own
# `gdrive:` remote — rclone's built-in OAuth, no Google Cloud client to set up).
#
# Per report, TWO files land in the shared folder (neither ever overwrites a prior one —
# both are timestamped, so history accrues):
#   1. <name>.tar.gz          detailed logs (for debugging)
#   2. <name>.summary.json    one-line summary row (the maintainer's collate step turns the
#                             folder of these into a single index CSV — the "same table")
#
# Logs are kept DETAILED (paths, event names, timings, errors preserved). Only obvious
# credential shapes are redacted as a safety net.
#
# Usage:  collect_telemetry.sh [--dry-run] [--folder <ID>] [--remote <name>]
#
# Config (first match wins): flag → env → ~/.claude/harness-telemetry.conf
#   DRIVE_FOLDER=<id>        $HARNESS_TELEMETRY_DRIVE_FOLDER   --folder   (required)
#   RCLONE_REMOTE=<name>     $HARNESS_TELEMETRY_RCLONE_REMOTE  --remote   (default: gdrive)
set -uo pipefail

LOGS_DIR="$HOME/vault/logs"
CONF="$HOME/.claude/harness-telemetry.conf"
ID_FILE="$HOME/.claude/harness-install-id"
DRY_RUN=0; FOLDER=""; REMOTE=""; IF_CONFIGURED=0; ONBOARDING_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --folder)  FOLDER="${2:?--folder needs a Drive folder ID}"; shift ;;
    --remote)  REMOTE="${2:?--remote needs an rclone remote name}"; shift ;;
    --if-configured) IF_CONFIGURED=1 ;;   # scheduled use: silently skip if no folder set
    --onboarding) ONBOARDING_FILE="${2:?--onboarding needs a JSON file}"; shift ;;  # upload an install/verify report instead of logs
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

conf_get() { [ -f "$CONF" ] && grep -m1 "^$1=" "$CONF" 2>/dev/null | cut -d= -f2- | tr -d ' "'; }

[ -z "$FOLDER" ] && FOLDER="${HARNESS_TELEMETRY_DRIVE_FOLDER:-$(conf_get DRIVE_FOLDER)}"
[ -z "$REMOTE" ] && REMOTE="${HARNESS_TELEMETRY_RCLONE_REMOTE:-$(conf_get RCLONE_REMOTE)}"
[ -z "$REMOTE" ] && REMOTE="gdrive"
# Internal default sink — the folder ID is NOT a secret (write access is Drive-controlled).
# Blank this for public/external distribution so it can't auto-report to the internal sink.
[ -z "$FOLDER" ] && FOLDER="1yqQdN1LBPh7TjYZD2UVpncbHzCljfg4R"
# Operator = who this machine belongs to, so the maintainer can give directed fixes (NOT anonymous
# for internal use). Set OPERATOR in the conf; falls back to git email, then $USER.
OPERATOR="${HARNESS_TELEMETRY_OPERATOR:-$(conf_get OPERATOR)}"
[ -z "$OPERATOR" ] && OPERATOR="$(git config --global user.email 2>/dev/null || true)"
[ -z "$OPERATOR" ] && OPERATOR="${USER:-unknown}"

if [ -z "$FOLDER" ] || [ "$FOLDER" = "REPLACE_WITH_DRIVE_FOLDER_ID" ]; then
  if [ "$IF_CONFIGURED" = "1" ]; then
    echo "telemetry not configured (no DRIVE_FOLDER) — skipping."; exit 0   # scheduled no-op
  fi
  echo "✗ No Drive folder configured. Set it (from the maintainer's setup):" >&2
  echo "    echo 'DRIVE_FOLDER=<folder-id>' >> $CONF" >&2
  exit 1
fi

# ── Stable, PII-free install id ────────────────────────────────────────────
if [ ! -f "$ID_FILE" ]; then
  (uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N) \
    | tr 'A-Z' 'a-z' > "$ID_FILE"
fi
INSTALL_ID="$(tr -d '[:space:]' < "$ID_FILE")"

# ── Provenance (no PII) ────────────────────────────────────────────────────
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"   # -P resolves symlink → repo
if HARNESS_VER="$(git -C "$SELF_DIR" rev-parse --short HEAD 2>/dev/null)"; then
  # flag a modified working tree so a hand-edited harness is visible in the data
  [ -n "$(git -C "$SELF_DIR" status --porcelain 2>/dev/null)" ] && HARNESS_VER="${HARNESS_VER}-dirty"
  HARNESS_DATE="$(git -C "$SELF_DIR" log -1 --format=%cI 2>/dev/null || echo unknown)"
else
  # non-git install (zip/tarball) — fall back to a shipped VERSION file at the repo root
  HARNESS_VER="$(head -1 "$SELF_DIR/../../../../VERSION" 2>/dev/null | tr -d '[:space:]')"
  [ -z "$HARNESS_VER" ] && HARNESS_VER="unknown"
  HARNESS_DATE="unknown"
fi
MACHINE_TAG="$( { hostname 2>/dev/null || echo unknown; } | shasum -a 256 2>/dev/null | cut -c1-12 )"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OS="$(uname -s 2>/dev/null || echo unknown)"

# ── Onboarding-report mode: upload the given verify-setup JSON, not the logs ───────────────
if [ -n "$ONBOARDING_FILE" ]; then
  [ -f "$ONBOARDING_FILE" ] || { echo "✗ onboarding file not found: $ONBOARDING_FILE" >&2; exit 1; }
  command -v rclone >/dev/null 2>&1 || { echo "✗ rclone not installed." >&2; exit 1; }
  rclone listremotes 2>/dev/null | grep -qx "${REMOTE}:" || { echo "✗ rclone remote '${REMOTE}:' not found." >&2; exit 1; }
  NAME="onboarding_${INSTALL_ID}_${TS}.json"
  UPD="$(mktemp -d "${TMPDIR:-/tmp}/onb.XXXXXX")"; cp "$ONBOARDING_FILE" "$UPD/$NAME"
  if rclone copy "$UPD/$NAME" "${REMOTE},root_folder_id=${FOLDER}:" --contimeout 30s --timeout 60s -q; then
    echo "✓ onboarding report uploaded: $NAME"; rm -rf "$UPD"; exit 0
  fi
  echo "✗ onboarding upload failed (is the folder shared to you as editor?)." >&2; rm -rf "$UPD"; exit 1
fi

[ -d "$LOGS_DIR" ] || { echo "✗ No logs at $LOGS_DIR — nothing to report." >&2; exit 1; }

# ── Lightweight summary (counts only — no secrets) ─────────────────────────
HOOKS="$LOGS_DIR/hooks.jsonl"
hook_rows=0; exit_nz=0; ws_deg=0; out_err=0; dj_fail=0
if [ -f "$HOOKS" ]; then
  hook_rows=$(wc -l < "$HOOKS" | tr -d ' ')
  exit_nz=$(grep -cE '"exit_code":[1-9]' "$HOOKS" 2>/dev/null || true)
  ws_deg=$(grep -c '"hook":"warm-start".*"outcome":"degraded"' "$HOOKS" 2>/dev/null || true)
  out_err=$(grep -cE '"outcome":"(error|fail)"' "$HOOKS" 2>/dev/null || true)
fi
[ -f "$LOGS_DIR/daily-jobs.jsonl" ] && dj_fail=$(grep -cE '"outcome":"(error|fail)"' "$LOGS_DIR/daily-jobs.jsonl" 2>/dev/null || true)

# ── Stage a redacted copy (keep detail; net obvious secrets only) ──────────
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/harness-telemetry.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$LOGS_DIR" "$STAGE/logs"
find "$STAGE/logs" -type f \( -name '*.jsonl' -o -name '*.log' -o -name '*.json' \) -print0 \
  | while IFS= read -r -d '' f; do
      LC_ALL=C sed -E \
        -e 's/(sk-|xox[bapr]-|ghp_|github_pat_|gho_|AIza|eyJ[A-Za-z0-9_-]{6,})[A-Za-z0-9._-]+/[REDACTED-TOKEN]/g' \
        -e 's/[Bb]earer[[:space:]]+[A-Za-z0-9._-]{12,}/Bearer [REDACTED]/g' \
        -e 's/(("?)(api[_-]?key|token|password|passwd|secret|access[_-]?token)("?)[[:space:]]*[:=][[:space:]]*"?)[A-Za-z0-9._-]{8,}/\1[REDACTED]/gI' \
        "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    done

BASE="harness-telemetry_${INSTALL_ID}_${TS}"
# summary.json — one flat object; the maintainer collate step reads these into the index CSV.
cat > "$STAGE/${BASE}.summary.json" <<EOF
{"collected_at_utc":"$TS","operator":"$OPERATOR","install_id":"$INSTALL_ID","machine_tag":"$MACHINE_TAG","harness_version":"$HARNESS_VER","harness_committed":"$HARNESS_DATE","os":"$OS","hook_rows":$hook_rows,"exit_nonzero":${exit_nz:-0},"warm_start_degraded":${ws_deg:-0},"outcome_errors":${out_err:-0},"daily_job_failures":${dj_fail:-0},"bundle_name":"${BASE}.tar.gz"}
EOF
cp "$STAGE/${BASE}.summary.json" "$STAGE/manifest.json"

OUT="$STAGE/${BASE}.tar.gz"
( cd "$STAGE" && tar czf "$OUT" logs manifest.json )
SIZE="$(du -h "$OUT" | cut -f1 | tr -d ' ')"

echo "── telemetry report ─────────────────────────────"
echo "  install_id : $INSTALL_ID"
echo "  version    : $HARNESS_VER ($HARNESS_DATE)   os: $OS   machine: $MACHINE_TAG"
echo "  errors     : exit≠0=${exit_nz:-0}  ws-degraded=${ws_deg:-0}  outcome-err=${out_err:-0}  daily-job-fails=${dj_fail:-0}  (of $hook_rows hook rows)"
echo "  bundle     : ${BASE}.tar.gz ($SIZE) + ${BASE}.summary.json"
echo "  dest       : rclone $REMOTE → folder $FOLDER"
echo "─────────────────────────────────────────────────"

if [ "$DRY_RUN" = "1" ]; then
  echo "[dry-run] not uploading. Staged at: $STAGE"
  trap - EXIT
  exit 0
fi

command -v rclone >/dev/null 2>&1 || { echo "✗ rclone not installed — bundle kept at $OUT." >&2; trap - EXIT; exit 1; }
if ! rclone listremotes 2>/dev/null | grep -qx "${REMOTE}:"; then
  echo "✗ rclone remote '${REMOTE}:' not found. Set one up (no Cloud key needed):" >&2
  echo "    rclone config    # n → name it '${REMOTE}' → type 'drive' → follow the browser OAuth" >&2
  echo "  bundle kept at: $OUT" >&2
  trap - EXIT; exit 1
fi

# root_folder_id override writes straight into the maintainer's shared folder (you own it).
DEST="${REMOTE},root_folder_id=${FOLDER}:"
if rclone copy "$OUT" "$DEST" --contimeout 30s --timeout 180s -q \
   && rclone copy "$STAGE/${BASE}.summary.json" "$DEST" --contimeout 30s --timeout 60s -q; then
  echo "✓ reported to Drive folder $FOLDER (bundle + summary row)"
  exit 0
fi
echo "✗ rclone upload failed. Check access to the shared folder (must be shared to you as editor)." >&2
echo "  bundle kept at: $OUT" >&2
trap - EXIT; exit 1
