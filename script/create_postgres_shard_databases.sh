#!/usr/bin/env bash
# Idempotent: CREATE DATABASE <base>_<n> for n in 0..COUNT-1 if missing.
# Used by CI and for local parallel RSpec + Postgres (./bin/polyrun with multiple workers).
#
# Env (optional):
#   DATABASE_URL                 — if set, base DB name is the last path segment (e.g. .../active_version_test)
#   ACTIVE_VERSION_PG_SHARD_BASE   — override base name (default: active_version_test)
#   ACTIVE_VERSION_PG_SHARD_COUNT  — shards 0..COUNT-1 (default: 5; align with POLYRUN_WORKERS)
#   PGHOST PGPORT PGUSER PGPASSWORD — libpq (defaults: localhost, 5432, postgres)
set -eo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BASE="${ACTIVE_VERSION_PG_SHARD_BASE:-active_version_test}"
if [[ -n "${DATABASE_URL:-}" ]] && [[ "$DATABASE_URL" =~ ^postgres(ql)?:// ]]; then
  db="${DATABASE_URL##*/}"
  db="${db%%\?*}"
  if [[ -n "$db" ]]; then
    BASE="$db"
  fi
fi

COUNT="${ACTIVE_VERSION_PG_SHARD_COUNT:-5}"
case "$COUNT" in ''|*[!0-9]*) COUNT=5 ;; esac
if [ "$COUNT" -lt 1 ]; then COUNT=1; fi
if [ "$COUNT" -gt 10 ]; then COUNT=10; fi

export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"

for i in $(seq 0 $((COUNT - 1))); do
  name="${BASE}_${i}"
  if psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '$name'" | grep -q 1; then
    continue
  fi
  psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -c "CREATE DATABASE \"$name\";"
done
