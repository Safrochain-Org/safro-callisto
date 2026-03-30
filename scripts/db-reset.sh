#!/usr/bin/env bash
# Drop the Callisto database, recreate it, and apply all schema migrations from scratch.
# Stops Callisto / anything using the DB first.
#
# Usage (from repo root):
#   ./scripts/db-reset.sh
#
# Same .env variables as db-init.sh (POSTGRES_*, PG_SUPERUSER, PGPASSWORD).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=db-common.sh
source "${SCRIPT_DIR}/db-common.sh"

db_common_load_env "$REPO_ROOT"

echo "==> Resetting database '${POSTGRES_DB}' (terminate connections, drop, recreate) ..."

psql_super() {
  psql -v ON_ERROR_STOP=1 -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$PG_SUPERUSER" -d postgres "$@"
}

if [[ "$(psql_super -tAc "SELECT current_setting('is_superuser')" | tr -d '[:space:]')" != "on" ]]; then
  echo "ERROR: ${PG_SUPERUSER} is not a superuser on ${POSTGRES_HOST}:${POSTGRES_PORT}." >&2
  echo "  Point POSTGRES_PORT at Docker Postgres (this repo publishes 127.0.0.1:5434). Port 5432 is often Homebrew." >&2
  echo "  Start stack: docker compose --env-file .env up -d postgres" >&2
  exit 1
fi

# Terminate backends connected to target DB
psql_super -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '${POSTGRES_DB}' AND pid <> pg_backend_pid();
" || true

if psql_super -tAc "SELECT 1 FROM pg_database WHERE datname='${POSTGRES_DB}'" | grep -q 1; then
  psql_super -c "DROP DATABASE \"${POSTGRES_DB}\";"
  echo "    Dropped database ${POSTGRES_DB}"
fi

# Ensure role exists (DROP DATABASE does not drop role)
if ! psql_super -tAc "SELECT 1 FROM pg_roles WHERE rolname='${POSTGRES_USER}'" | grep -q 1; then
  psql_super -v "pw=$POSTGRES_PASSWORD" \
    -c "CREATE ROLE \"${POSTGRES_USER}\" WITH LOGIN PASSWORD :'pw'"
  echo "    Created role ${POSTGRES_USER}"
fi

if ! psql_super -c "CREATE DATABASE \"${POSTGRES_DB}\" OWNER \"${POSTGRES_USER}\";"; then
  echo "" >&2
  echo "CREATE DATABASE failed (need superuser or CREATEDB). Fix one of:" >&2
  echo "  • Docker: PG_SUPERUSER=callisto (same as POSTGRES_USER); POSTGRES_PORT = host port to the container" >&2
  echo "  • Local Postgres: PG_SUPERUSER=postgres and PGPASSWORD for that role, or: ALTER ROLE callisto CREATEDB" >&2
  echo "  • Or: psql -U postgres -c \"ALTER ROLE ${POSTGRES_USER} CREATEDB;\"" >&2
  exit 1
fi
psql_super -c "GRANT ALL PRIVILEGES ON DATABASE \"${POSTGRES_DB}\" TO \"${POSTGRES_USER}\";"

echo "    Recreated database ${POSTGRES_DB}"

export PGPASSWORD="${POSTGRES_PASSWORD}"
db_common_run_migrations "$REPO_ROOT"

echo "==> db-reset complete (clean schema, empty data)."
echo "    Next: restart Hasura + apply metadata → ./scripts/hasura-metadata-apply.sh"
