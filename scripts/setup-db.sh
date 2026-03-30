#!/usr/bin/env bash
# Create Postgres role + database for Callisto (run once, or after reset-db).
# Sources repo `.env` when present. Defaults match Docker production: 127.0.0.1:5434.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
fi

DB_USER="${POSTGRES_USER:-callisto}"
DB_PASS="${POSTGRES_PASSWORD:-password}"
DB_NAME="${POSTGRES_DB:-callisto}"
DB_HOST="${POSTGRES_HOST:-127.0.0.1}"
DB_PORT="${POSTGRES_PORT:-5434}"
# Docker postgres image: POSTGRES_USER is superuser. Override for local socket installs.
PG_SUPER="${PG_SUPERUSER:-${POSTGRES_USER:-callisto}}"
export PGPASSWORD="${POSTGRES_SUPER_PASSWORD:-$POSTGRES_PASSWORD}"

# Superuser connection:
# - On Debian/Ubuntu, "postgres" over TCP often has no password; use peer auth via sudo + unix socket.
# - Docker / remote TCP: use POSTGRES_USER + POSTGRES_PASSWORD (see PG_SUPERUSER).
psql_super() {
  if [ "$PG_SUPER" = "postgres" ] && command -v sudo >/dev/null; then
    sudo -u postgres psql -d postgres "$@"
  else
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$PG_SUPER" -d postgres "$@"
  fi
}

echo "==> Creating role '$DB_USER' (if not exists)..."
psql_super -tc "SELECT 1 FROM pg_roles WHERE rolname = '$DB_USER'" \
  | grep -q 1 \
  || psql_super -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"

echo "==> Creating database '$DB_NAME' (if not exists)..."
psql_super -tc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" \
  | grep -q 1 \
  || psql_super -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

echo "==> Granting privileges..."
psql_super -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"

echo "==> Done. Database '$DB_NAME' ready for user '$DB_USER'."
