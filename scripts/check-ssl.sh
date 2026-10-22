#!/usr/bin/env bash
# Runs the same test BEFORE and AFTER enabling "Enforce SSL".
# It connects with a deliberately wrong password and shows at which stage the connection is refused (no real password is used).
#
# Usage:
#   export PGHOST="aws-0-<region>.pooler.supabase.com"   # Dashboard: Connect -> Session pooler
#   export PGUSER="postgres.<PROJECT_REF>"
#   ./scripts/check-ssl.sh
set -u

: "${PGHOST:?Set PGHOST (see the README)}"
: "${PGUSER:?Set PGUSER (see the README)}"
command -v psql >/dev/null || { echo "psql not found (install the PostgreSQL client)"; exit 1; }

for mode in disable require; do
  printf "sslmode=%-8s -> " "$mode"
  # PGPASSWORD is a deliberately wrong value. Setting it here overrides any real password in your environment.
  PGPASSWORD=wrong-on-purpose PGCONNECT_TIMEOUT=10 psql \
    "host=$PGHOST port=5432 dbname=postgres user=$PGUSER sslmode=$mode" \
    -c "select 1" 2>&1 | head -1
done
