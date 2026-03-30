#!/usr/bin/env bash
# Shared helpers for db-init.sh / db-reset.sh (sourced, not executed directly).
set -euo pipefail

db_common_load_env() {
  local repo_root="${1:?}"
  if [[ -f "${repo_root}/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${repo_root}/.env"
    set +a
  fi

  export POSTGRES_USER="${POSTGRES_USER:-callisto}"
  export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-password}"
  export POSTGRES_DB="${POSTGRES_DB:-callisto}"
  export POSTGRES_HOST="${POSTGRES_HOST:-127.0.0.1}"
  # Default 5434 matches docker-compose.yml host publish (avoids Homebrew Postgres on 5432).
  export POSTGRES_PORT="${POSTGRES_PORT:-5434}"
  # Role used for CREATE/DROP DATABASE / CREATE ROLE. Default = POSTGRES_USER so the official
  # postgres Docker image works (superuser is POSTGRES_USER; there is no "postgres" role).
  # Local Homebrew Postgres: if callisto is not superuser, set PG_SUPERUSER=postgres (+ PGPASSWORD).
  export PG_SUPERUSER="${PG_SUPERUSER:-$POSTGRES_USER}"
  export PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}"
}

db_common_schema_dir() {
  local repo_root="${1:?}"
  echo "${repo_root}/database/schema"
}

# Apply all database/schema/*.sql in lexical order with ON_ERROR_STOP.
db_common_run_migrations() {
  local repo_root="${1:?}"
  local schema_dir
  schema_dir="$(db_common_schema_dir "$repo_root")"

  if [[ ! -d "$schema_dir" ]]; then
    echo "ERROR: schema directory not found: $schema_dir" >&2
    exit 1
  fi

  echo "==> Applying schema files from ${schema_dir} ..."
  shopt -s nullglob
  local files=("${schema_dir}"/*.sql)
  shopt -u nullglob
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "ERROR: no *.sql files in ${schema_dir}" >&2
    exit 1
  fi

  local f
  for f in "${files[@]}"; do
    echo "    $(basename "$f")"
    psql -v ON_ERROR_STOP=1 \
      -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
      -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
      -f "$f"
  done
  echo "==> Schema migration complete."
}
