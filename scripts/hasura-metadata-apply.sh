#!/usr/bin/env bash
# Restart Hasura (so it rebuilds hdb_catalog after db-reset), wait for health, then hasura metadata apply.
#
# Usage (from repo root):
#   ./scripts/hasura-metadata-apply.sh
#
# Skip Docker restart (normal metadata refresh only):
#   SKIP_HASURA_RESTART=1 ./scripts/hasura-metadata-apply.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HASURA_ENDPOINT="${HASURA_ENDPOINT:-http://127.0.0.1:8080}"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

cd "${REPO_ROOT}"

if [[ "${SKIP_HASURA_RESTART:-0}" != "1" ]]; then
  echo "==> Restarting Hasura (recreates hdb_catalog if the DB was recreated)..."
  if ! docker compose --env-file .env restart hasura 2>/dev/null; then
    echo "WARN: docker compose restart hasura failed (is Docker running?). Trying to continue..." >&2
  fi

  echo "==> Waiting for ${HASURA_ENDPOINT}/healthz ..."
  ok=0
  for _ in $(seq 1 45); do
    if curl -sf "${HASURA_ENDPOINT}/healthz" >/dev/null 2>&1; then
      ok=1
      break
    fi
    sleep 2
  done
  if [[ "$ok" != "1" ]]; then
    echo "ERROR: Hasura not healthy. Logs: docker logs safro-hasura --tail 80" >&2
    exit 1
  fi
  # Brief pause so catalog migrations can finish after healthz
  sleep 3
fi

admin_args=()
if [[ -n "${HASURA_GRAPHQL_ADMIN_SECRET:-}" ]]; then
  admin_args=(--admin-secret "${HASURA_GRAPHQL_ADMIN_SECRET}")
fi

echo "==> hasura metadata apply"
(cd "${REPO_ROOT}/hasura" && hasura metadata apply --endpoint "${HASURA_ENDPOINT}" "${admin_args[@]}")
echo "==> Hasura metadata apply complete."
