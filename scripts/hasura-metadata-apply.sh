#!/usr/bin/env bash
# Apply Hasura metadata from safro-callisto/hasura (CLI must see hasura/config.yaml).
# Run from repo root: ./scripts/hasura-metadata-apply.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export HASURA_GRAPHQL_ADMIN_SECRET="${HASURA_GRAPHQL_ADMIN_SECRET:-myadminsecretkey}"
cd "${ROOT}/hasura"
exec hasura metadata apply --endpoint http://localhost:8080
