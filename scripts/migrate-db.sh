#!/usr/bin/env bash
# Apply SQL schema under database/schema/*.sql (required before first `callisto start`).
# Sources repo `.env` when present — set POSTGRES_HOST=127.0.0.1 and POSTGRES_PORT=5434 for Docker production.
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

export PGPASSWORD="$DB_PASS"

SCHEMA_DIR="$(cd "$(dirname "$0")/../database/schema" && pwd)"

echo "==> Applying schema files from $SCHEMA_DIR ..."
for f in "$SCHEMA_DIR"/*.sql; do
  echo "    $(basename "$f")"
  psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$f" -q
done

echo "==> Schema migration complete."
