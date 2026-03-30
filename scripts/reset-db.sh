#!/usr/bin/env bash
# Drop and recreate Callisto DB + schema. Destroys all indexed data.
# Sources repo `.env`. Defaults: 127.0.0.1:5434, superuser = POSTGRES_USER (Docker image superuser).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
fi

DB_USER="${POSTGRES_USER:-callisto}"
DB_NAME="${POSTGRES_DB:-callisto}"
DB_HOST="${POSTGRES_HOST:-127.0.0.1}"
DB_PORT="${POSTGRES_PORT:-5434}"
PG_SUPER="${PG_SUPERUSER:-${POSTGRES_USER:-callisto}}"
export PGPASSWORD="${POSTGRES_SUPER_PASSWORD:-$POSTGRES_PASSWORD}"

psql_super() {
  if [ "$PG_SUPER" = "postgres" ] && command -v sudo >/dev/null; then
    sudo -u postgres psql -d postgres "$@"
  else
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$PG_SUPER" -d postgres "$@"
  fi
}

echo "==> Terminating active connections to '$DB_NAME'..."
psql_super -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" -q

echo "==> Dropping database '$DB_NAME'..."
psql_super -c "DROP DATABASE IF EXISTS $DB_NAME;"

# Do not DROP ROLE here: Docker's official image makes POSTGRES_USER the only superuser;
# dropping it would break the next connection. We only wipe data by recreating the DB + schema.

echo "==> Recreating database and schema..."
"$(dirname "$0")/setup-db.sh"
"$(dirname "$0")/migrate-db.sh"

echo "==> Reset complete. Clean database ready."
