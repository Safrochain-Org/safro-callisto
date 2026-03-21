#!/usr/bin/env bash
# Apply Hasura metadata from safro-callisto/hasura (CLI must see hasura/config.yaml).
# Run from repo root: ./scripts/hasura-metadata-apply.sh
# Loads ../.env when present so the secret matches docker compose --env-file .env (production).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
fi
export HASURA_GRAPHQL_ADMIN_SECRET="${HASURA_GRAPHQL_ADMIN_SECRET:-myadminsecretkey}"
cd "${ROOT}/hasura"
exec hasura metadata apply --endpoint http://localhost:8080
