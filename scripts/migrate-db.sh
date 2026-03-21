#!/usr/bin/env bash
set -euo pipefail

DB_USER="${POSTGRES_USER:-callisto}"
DB_PASS="${POSTGRES_PASSWORD:-password}"
DB_NAME="${POSTGRES_DB:-callisto}"
DB_HOST="${POSTGRES_HOST:-localhost}"
DB_PORT="${POSTGRES_PORT:-5432}"

export PGPASSWORD="$DB_PASS"

SCHEMA_DIR="$(cd "$(dirname "$0")/../database/schema" && pwd)"

echo "==> Applying schema files from $SCHEMA_DIR ..."
for f in "$SCHEMA_DIR"/*.sql; do
  echo "    $(basename "$f")"
  psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$f" -q
done

echo "==> Schema migration complete."
