#!/usr/bin/env bash
# Calls the security-status function every few seconds and prints one line per call: time, HTTP status, seconds taken,
# and the database start time (it changes when Postgres restarts). Use it while you restart the database to see when the API stops and returns.
#
# Usage:
#   export STATUS_URL="https://<PROJECT_REF>.supabase.co/functions/v1/security-status"
#   export PUBLISHABLE_KEY="<your publishable key>"
#   ./scripts/poll.sh 3        # every 3 seconds; stop with Ctrl-C
set -u
: "${STATUS_URL:?Set STATUS_URL (see the README)}"
: "${PUBLISHABLE_KEY:?Set PUBLISHABLE_KEY (see the README)}"
every="${1:-3}"
while true; do
  out=$(curl -s -m 20 -o /tmp/poll-body.$$ -w "%{http_code} %{time_total}" -X POST "$STATUS_URL" \
        -H "apikey: $PUBLISHABLE_KEY" -H "Content-Type: application/json" -d '{}' 2>/dev/null)
  code="${out%% *}"; secs="${out##* }"
  started=$(python3 -c "import json;print(json.load(open('/tmp/poll-body.$$'))['database']['started_at'])" 2>/dev/null || echo "-")
  printf "%s  http=%s  %ss  postgres_started_at=%s\n" "$(date -u +%H:%M:%S)" "$code" "$secs" "$started"
  sleep "$every"
done
