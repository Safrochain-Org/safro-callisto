#!/usr/bin/env bash
set -euo pipefail

DB_USER="${POSTGRES_USER:-callisto}"
DB_NAME="${POSTGRES_DB:-callisto}"
DB_HOST="${POSTGRES_HOST:-localhost}"
DB_PORT="${POSTGRES_PORT:-5432}"
PG_SUPER="${PG_SUPERUSER:-$(whoami)}"

echo "==> Terminating active connections to '$DB_NAME'..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$PG_SUPER" -d postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" -q

echo "==> Dropping database '$DB_NAME'..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$PG_SUPER" -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"

echo "==> Dropping role '$DB_USER'..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$PG_SUPER" -d postgres -c "DROP ROLE IF EXISTS $DB_USER;"

echo "==> Recreating from scratch..."
"$(dirname "$0")/setup-db.sh"
"$(dirname "$0")/migrate-db.sh"

echo "==> Reset complete. Clean database ready."
