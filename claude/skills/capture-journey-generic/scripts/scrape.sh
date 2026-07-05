#!/usr/bin/env bash
# Scrape a user's Mixpanel events via the stream API and save to JSON.
# Usage: scrape.sh <distinct_id> <from_date> <to_date> <output_path>
# Requires: MP_CSRFTOKEN + MP_SESSIONID env vars (Mixpanel web session cookies).
# Optional: MP_PROJECT_ID (default 2879659), MP_WORKSPACE_ID (default 3411815).

set -euo pipefail

DISTINCT_ID="${1:?distinct_id required}"
FROM_DATE="${2:?from_date required (YYYY-MM-DD)}"
TO_DATE="${3:?to_date required (YYYY-MM-DD)}"
OUT="${4:?output path required}"

if [[ -z "${MP_SESSIONID:-}" || -z "${MP_CSRFTOKEN:-}" ]]; then
  echo "ERROR: set MP_SESSIONID and MP_CSRFTOKEN env vars (from mixpanel.com cookies)." >&2
  exit 2
fi

PROJECT_ID="${MP_PROJECT_ID:-2879659}"
WORKSPACE_ID="${MP_WORKSPACE_ID:-3411815}"

# URL-encode the distinct_ids JSON array
DIDS=$(printf '%%5B%%22%s%%22%%5D' "$DISTINCT_ID")

URL="https://mixpanel.com/api/query/stream/query?project_id=${PROJECT_ID}&workspace_id=${WORKSPACE_ID}&distinct_ids=${DIDS}&from_date=${FROM_DATE}&to_date=${TO_DATE}&limit=1000"

HTTP=$(/usr/bin/curl -s -o "$OUT" -w '%{http_code}' "$URL" \
  -H 'authorization: Session' \
  -H 'accept: */*' \
  -H "project-id: ${PROJECT_ID}" \
  -H "referer: https://mixpanel.com/project/${PROJECT_ID}/view/${WORKSPACE_ID}/app/profile" \
  -b "csrftoken=${MP_CSRFTOKEN}; sessionid=${MP_SESSIONID}")

if [[ "$HTTP" != "200" ]]; then
  echo "ERROR: stream API returned HTTP $HTTP" >&2
  /usr/bin/head -c 500 "$OUT" >&2
  exit 1
fi

# Sanity: check JSON parses and has events
COUNT=$(/usr/bin/python3 -c "import json,sys; d=json.load(open('$OUT')); print(len(d['results']['events']))")
echo "Scraped $COUNT events → $OUT (project=${PROJECT_ID})"
