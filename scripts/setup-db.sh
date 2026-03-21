#!/usr/bin/env bash
set -euo pipefail

DB_USER="${POSTGRES_USER:-callisto}"
DB_PASS="${POSTGRES_PASSWORD:-password}"
DB_NAME="${POSTGRES_DB:-callisto}"
DB_HOST="${POSTGRES_HOST:-localhost}"
DB_PORT="${POSTGRES_PORT:-5432}"
PG_SUPER="${PG_SUPERUSER:-$(whoami)}"

echo "==> Creating role '$DB_USER' (if not exists)..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$PG_SUPER" -d postgres -tc \
  "SELECT 1 FROM pg_roles WHERE rolname = '$DB_USER'" \
  | grep -q 1 \
  || psql -h "$DB_HOST" -p "$DB_PORT" -U "$PG_SUPER" -d postgres -c \
       "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"

echo "==> Creating database '$DB_NAME' (if not exists)..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$PG_SUPER" -d postgres -tc \
  "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" \
  | grep -q 1 \
  || psql -h "$DB_HOST" -p "$DB_PORT" -U "$PG_SUPER" -d postgres -c \
       "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

echo "==> Granting privileges..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$PG_SUPER" -d postgres -c \
  "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"

echo "==> Done. Database '$DB_NAME' ready for user '$DB_USER'."
