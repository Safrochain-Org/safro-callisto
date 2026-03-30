#!/usr/bin/env bash
# Last indexed block height in Postgres (quiet alternative to debug logging).
# Uses the same env as verify-callisto-db.sh / docker .env when present.
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
PORT="${POSTGRES_PORT:-5432}"
export PGPASSWORD="$PASS"
psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -c "SELECT MAX(height) AS last_indexed_height FROM block;"
