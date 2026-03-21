#!/usr/bin/env bash
# Apply Hasura metadata. Run from repo root:
#   ./scripts/hasura-metadata-apply.sh
#
# Loads .env so HASURA_GRAPHQL_ADMIN_SECRET matches docker compose --env-file .env.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
fi
SECRET="${HASURA_GRAPHQL_ADMIN_SECRET:-myadminsecretkey}"
cd "${ROOT}/hasura"
exec hasura metadata apply \
  --endpoint http://127.0.0.1:8080 \
  --admin-secret "$SECRET"
