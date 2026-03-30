#!/usr/bin/env bash
# Safro Callisto stack: Docker (Postgres + Hasura), Hasura metadata, Callisto binary.
# Run from safro-callisto/: ./scripts/dev-stack.sh <command>
#
# Commands:
#   all       Stop Callisto → docker compose … down -v → up -d (docker-compose.yml + docker-compose.dev.yml) →
#             wait Postgres & Hasura → hasura metadata apply → Callisto in background (logs/callisto-sync.log)
#   reset     Same as all except does not start Callisto
#   up        docker compose … up -d (keeps data) → wait → hasura metadata apply
#   stop      Stop Callisto only (Docker keeps running)
#   build     make build
#   start     Foreground Callisto (builds if build/callisto missing)
#   start-bg  Background Callisto + log file
#   logs      tail -f logs/callisto-sync.log
#   check     Verify Docker, compose, curl, hasura CLI, paths, Callisto config, and build tools
#   help      This usage
#
# Optional: SKIP_DEV_STACK_CHECKS=1 to skip prerequisite checks (not recommended).
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="${ROOT}/logs"
LOG_FILE="${LOG_DIR}/callisto-sync.log"
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.dev.yml"
CALLISTO_HOME="${ROOT}/.callisto"
CALLISTO_BIN="${ROOT}/build/callisto"

if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
fi

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  local c="$1"
  shift
  command -v "$c" &>/dev/null || die "Missing '${c}' in PATH. $*"
}

checks_enabled() {
  [[ "${SKIP_DEV_STACK_CHECKS:-0}" != "1" ]]
}

check_docker_daemon() {
  need_cmd docker "Install Docker Desktop or the Docker Engine package."
  docker info &>/dev/null || die "Docker daemon is not running or not accessible (try: docker info)."
}

check_docker_compose() {
  check_docker_daemon
  docker compose version &>/dev/null || die "'docker compose' (Compose v2 plugin) is required."
}

check_curl() {
  need_cmd curl "Install curl (used to wait for Hasura health)."
}

check_hasura_cli() {
  need_cmd hasura "Install Hasura CLI: https://hasura.io/docs/latest/hasura-cli/install-hasura-cli/"
}

check_callisto_build_tools() {
  need_cmd make "Required to build Callisto."
  need_cmd go "Required to build Callisto (Go toolchain)."
  [[ -f "${ROOT}/Makefile" ]] || die "Missing ${ROOT}/Makefile"
}

check_callisto_config() {
  [[ -f "${CALLISTO_HOME}/config.yaml" ]] || die "Missing Callisto config: ${CALLISTO_HOME}/config.yaml"
}

check_compose_project() {
  [[ -f "${ROOT}/docker-compose.yml" ]] || die "Missing ${ROOT}/docker-compose.yml"
  [[ -f "${ROOT}/docker-compose.dev.yml" ]] || die "Missing ${ROOT}/docker-compose.dev.yml"
}

check_hasura_project() {
  [[ -f "${ROOT}/hasura/config.yaml" ]] || die "Missing ${ROOT}/hasura/config.yaml (Hasura project root)."
}

require_stack_paths() {
  checks_enabled || return 0
  check_compose_project
  check_hasura_project
}

require_for_compose() {
  checks_enabled || return 0
  check_docker_compose
  check_curl
  check_hasura_cli
  require_stack_paths
  check_callisto_config
}

require_for_callisto_run() {
  checks_enabled || return 0
  check_callisto_config
  if [[ ! -x "$CALLISTO_BIN" ]]; then
    check_callisto_build_tools
  fi
}

require_for_build() {
  checks_enabled || return 0
  check_callisto_build_tools
  check_callisto_config
}

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
}

wait_postgres() {
  echo "Waiting for Postgres (safro-postgres)..."
  local i
  for i in $(seq 1 60); do
    if docker exec safro-postgres pg_isready -U "${POSTGRES_USER:-callisto}" -d "${POSTGRES_DB:-callisto}" &>/dev/null; then
      echo "Postgres is ready."
      return 0
    fi
    sleep 1
  done
  die "Postgres did not become ready in time (container safro-postgres)."
}

wait_hasura() {
  echo "Waiting for Hasura on :8080..."
  local i
  for i in $(seq 1 60); do
    if curl -sf "http://localhost:8080/healthz" &>/dev/null || curl -sf "http://localhost:8080/v1/version" &>/dev/null; then
      echo "Hasura is up."
      return 0
    fi
    sleep 1
  done
  die "Hasura did not become ready in time (http://localhost:8080)."
}

cmd_stop() {
  echo "Stopping Callisto (if running)..."
  pkill -f '[/]build/callisto start' 2>/dev/null || true
  pkill -f '[/]callisto start --home' 2>/dev/null || true
}

cmd_reset() {
  require_for_compose
  cmd_stop
  cd "${ROOT}"
  echo "Docker: removing containers and postgres volume..."
  ${COMPOSE} down -v
  echo "Docker: starting Postgres + Hasura..."
  ${COMPOSE} up -d
  wait_postgres
  echo "Applying database schema (database/schema/*.sql)..."
  "${ROOT}/scripts/migrate-db.sh"
  wait_hasura
  sleep 2
  echo "Applying Hasura metadata..."
  "${ROOT}/scripts/hasura-metadata-apply.sh"
  echo "Reset done. GraphQL: http://localhost:8080/v1/graphql"
}

cmd_up() {
  require_for_compose
  cd "${ROOT}"
  ${COMPOSE} up -d
  wait_postgres
  wait_hasura
  sleep 2
  "${ROOT}/scripts/hasura-metadata-apply.sh"
  echo "Stack is up. GraphQL: http://localhost:8080/v1/graphql"
}

cmd_build() {
  require_for_build
  cd "${ROOT}"
  make build
}

ensure_binary() {
  if [[ ! -x "$CALLISTO_BIN" ]]; then
    echo "Binary missing; running make build..."
    cmd_build
  fi
}

cmd_start() {
  require_for_callisto_run
  ensure_binary
  cd "${CALLISTO_HOME}"
  exec "$CALLISTO_BIN" start --home "$CALLISTO_HOME"
}

cmd_start_bg() {
  require_for_callisto_run
  ensure_binary
  mkdir -p "${LOG_DIR}"
  echo "Appending to ${LOG_FILE}"
  (
    cd "${CALLISTO_HOME}"
    "$CALLISTO_BIN" start --home "$CALLISTO_HOME" 2>&1 | tee -a "${LOG_FILE}"
  ) &
  local pid=$!
  echo "Callisto started in background (shell job PID ${pid})."
  echo "  tail logs: ./scripts/dev-stack.sh logs"
  echo "  stop:      ./scripts/dev-stack.sh stop"
}

cmd_logs() {
  mkdir -p "${LOG_DIR}"
  touch "${LOG_FILE}"
  tail -f "${LOG_FILE}"
}

cmd_all() {
  cmd_reset
  cmd_start_bg
}

cmd_check() {
  echo "Prerequisite check (safro-callisto stack)..."
  check_docker_compose
  check_curl
  check_hasura_cli
  require_stack_paths
  check_callisto_config
  if [[ -x "$CALLISTO_BIN" ]]; then
    echo "OK: ${CALLISTO_BIN} exists and is executable."
  else
    check_callisto_build_tools
    echo "OK: Go toolchain present (build ${CALLISTO_BIN} with: ./scripts/dev-stack.sh build)."
  fi
  echo "All checks passed."
}

main() {
  local sub="${1:-help}"
  case "${sub}" in
    help|-h|--help) usage ;;
    check)          cmd_check ;;
    reset)          cmd_reset ;;
    up)             cmd_up ;;
    stop)           cmd_stop ;;
    build)          cmd_build ;;
    start)          cmd_start ;;
    start-bg)       cmd_start_bg ;;
    logs)           cmd_logs ;;
    all)            cmd_all ;;
    *)
      echo "Unknown command: ${sub}"
      usage
      exit 1
      ;;
  esac
}

main "$@"
