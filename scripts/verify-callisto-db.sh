#!/usr/bin/env bash
# Test that Postgres accepts the callisto credentials from .env (same as Hasura).
# Usage: from repo root: ./scripts/verify-callisto-db.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
fi
USER="${POSTGRES_USER:-callisto}"
PASS="${POSTGRES_PASSWORD:-password}"
DB="${POSTGRES_DB:-callisto}"
HOST="${POSTGRES_HOST:-127.0.0.1}"
PORT="${POSTGRES_PORT:-5434}"
export PGPASSWORD="$PASS"
echo "==> Testing: psql -h $HOST -p $PORT -U $USER -d $DB"
psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -c "select 1 as ok;"
echo "==> OK — use the same POSTGRES_PASSWORD in .callisto/config.yaml database.url"
