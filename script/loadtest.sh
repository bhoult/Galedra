#!/usr/bin/env bash
# Runs script/loadtest.js against a node, using the official k6 image so
# nothing has to be installed locally (Stage 26).
#
#   BASE_URL=https://staging.example script/loadtest.sh
#   BASE_URL=... ASSISTANT_TOKEN=gal_... READERS=40 script/loadtest.sh
#
# The write scenario appends real contributions, so this refuses a URL that
# looks like the live node unless LOADTEST_I_MEAN_IT=1 is set.
set -euo pipefail

: "${BASE_URL:?set BASE_URL to the node to test, e.g. https://staging.example}"

if [[ "$BASE_URL" == *"galedra.org"* && "${LOADTEST_I_MEAN_IT:-}" != "1" ]]; then
  echo "Refusing: $BASE_URL looks like the live node, and the write scenario appends real" >&2
  echo "contributions. Point this at a staging node, or set LOADTEST_I_MEAN_IT=1." >&2
  exit 1
fi

exec docker run --rm -i --network host \
  -e BASE_URL="$BASE_URL" \
  -e ASSISTANT_TOKEN="${ASSISTANT_TOKEN:-}" \
  -e READERS="${READERS:-20}" \
  -e SCANS_PER_MIN="${SCANS_PER_MIN:-4}" \
  -e WRITES_PER_MIN="${WRITES_PER_MIN:-6}" \
  grafana/k6:latest run - < "$(dirname "$0")/loadtest.js"
