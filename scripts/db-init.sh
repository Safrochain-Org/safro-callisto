#!/usr/bin/env bash
# Create PostgreSQL role + database (if missing) and apply all Callisto schema SQL files.
#
# Usage (from repo root):
#   ./scripts/db-init.sh
#
# Expects a reachable Postgres. Set in .env (optional):
#   POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB POSTGRES_HOST POSTGRES_PORT
#   PG_SUPERUSER   — must be able to CREATE DATABASE (default: POSTGRES_USER, for Docker postgres).
#                    Local cluster: set PG_SUPERUSER=postgres if callisto is not superuser.
#   PGPASSWORD     — password for PG_SUPERUSER (defaults to POSTGRES_PASSWORD)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=db-common.sh
source "${SCRIPT_DIR}/db-common.sh"

db_common_load_env "$REPO_ROOT"

echo "==> Ensuring database '${POSTGRES_DB}' and user '${POSTGRES_USER}' exist ..."

psql_super() {
  psql -v ON_ERROR_STOP=1 -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$PG_SUPERUSER" -d postgres "$@"
}

if [[ "$(psql_super -tAc "SELECT current_setting('is_superuser')" | tr -d '[:space:]')" != "on" ]]; then
  echo "ERROR: ${PG_SUPERUSER} is not a superuser on ${POSTGRES_HOST}:${POSTGRES_PORT}." >&2
  echo "  Point POSTGRES_PORT at Docker Postgres (this repo publishes 127.0.0.1:5434). Port 5432 is often Homebrew." >&2
  echo "  Start stack: docker compose --env-file .env up -d postgres" >&2
  exit 1
fi

# Role (if not exists) — PASSWORD :'pw' lets psql quote special characters safely
if ! psql_super -tAc "SELECT 1 FROM pg_roles WHERE rolname='${POSTGRES_USER}'" | grep -q 1; then
  psql_super -v "pw=$POSTGRES_PASSWORD" \
    -c "CREATE ROLE \"${POSTGRES_USER}\" WITH LOGIN PASSWORD :'pw'"
  echo "    Created role ${POSTGRES_USER}"
else
  echo "    Role ${POSTGRES_USER} already exists"
fi

# Database (if not exists)
if ! psql_super -tAc "SELECT 1 FROM pg_database WHERE datname='${POSTGRES_DB}'" | grep -q 1; then
  if ! psql_super -c "CREATE DATABASE \"${POSTGRES_DB}\" OWNER \"${POSTGRES_USER}\";"; then
    echo "" >&2
    echo "CREATE DATABASE failed (need superuser or CREATEDB). See comments in db-init.sh / .env.example" >&2
    exit 1
  fi
  echo "    Created database ${POSTGRES_DB}"
else
  echo "    Database ${POSTGRES_DB} already exists"
fi

psql_super -c "GRANT ALL PRIVILEGES ON DATABASE \"${POSTGRES_DB}\" TO \"${POSTGRES_USER}\";"

export PGPASSWORD="${POSTGRES_PASSWORD}"
db_common_run_migrations "$REPO_ROOT"

echo "==> db-init complete."
