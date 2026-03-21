#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO_VERSION="1.23.9"
SAFROCHAIN_REPO="https://github.com/Safrochain-Org/safrochain-node.git"
SAFROCHAIN_BRANCH="release/v0.1.0"
POSTGRES_USER="${POSTGRES_USER:-callisto}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-password}"
POSTGRES_DB="${POSTGRES_DB:-callisto}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
HASURA_PORT="${HASURA_PORT:-8080}"
CALLISTO_ACTIONS_PORT="${CALLISTO_ACTIONS_PORT:-3001}"
CALLISTO_HOME="${SCRIPT_DIR}/.callisto"
TARGET_HEIGHT=6835787

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }

##############################################################################
# 1. Install Go
##############################################################################
install_go() {
  if command -v go &>/dev/null; then
    CURRENT_GO=$(go version | grep -oP '\d+\.\d+\.\d+' || true)
    if [[ "$CURRENT_GO" == "$GO_VERSION" ]]; then
      log "Go $GO_VERSION already installed"
      return
    fi
    warn "Go $CURRENT_GO found, need $GO_VERSION"
  fi

  log "Installing Go $GO_VERSION ..."
  ARCH=$(uname -m)
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  case "$ARCH" in
    x86_64)  GOARCH="amd64" ;;
    aarch64|arm64) GOARCH="arm64" ;;
    *) err "Unsupported architecture: $ARCH" ;;
  esac

  GO_TAR="go${GO_VERSION}.${OS}-${GOARCH}.tar.gz"
  GO_URL="https://go.dev/dl/${GO_TAR}"

  curl -fsSL "$GO_URL" -o "/tmp/${GO_TAR}"
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "/tmp/${GO_TAR}"
  rm "/tmp/${GO_TAR}"

  export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"
  export GOPATH="$HOME/go"

  if ! grep -q '/usr/local/go/bin' "$HOME/.zshrc" 2>/dev/null; then
    echo 'export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"' >> "$HOME/.zshrc"
    echo 'export GOPATH="$HOME/go"' >> "$HOME/.zshrc"
  fi

  log "Go $(go version) installed"
}

##############################################################################
# 2. Install safrochaind
##############################################################################
install_safrochaind() {
  if command -v safrochaind &>/dev/null; then
    log "safrochaind already installed: $(safrochaind version 2>&1 || true)"
    return
  fi

  log "Cloning safrochain-node ..."
  SAFRO_BUILD_DIR="/tmp/safrochain-node-build"
  rm -rf "$SAFRO_BUILD_DIR"
  git clone "$SAFROCHAIN_REPO" "$SAFRO_BUILD_DIR"
  cd "$SAFRO_BUILD_DIR"
  git checkout "$SAFROCHAIN_BRANCH"

  log "Building safrochaind ..."
  make install
  cd "$SCRIPT_DIR"
  rm -rf "$SAFRO_BUILD_DIR"

  log "safrochaind installed: $(safrochaind version 2>&1 || true)"
}

##############################################################################
# 3. Build Callisto
##############################################################################
build_callisto() {
  log "Building callisto ..."
  cd "$SCRIPT_DIR"
  make build
  log "Callisto built at ${SCRIPT_DIR}/build/callisto"
}

##############################################################################
# 4. Docker: PostgreSQL + Hasura
##############################################################################
start_docker_services() {
  if ! command -v docker &>/dev/null; then
    err "Docker is not installed. Please install Docker first."
  fi

  log "Starting PostgreSQL and Hasura via docker-compose ..."
  cd "$SCRIPT_DIR"
  docker compose -f docker-compose.yml -f docker-compose.dev.yml down -v 2>/dev/null || true
  docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d

  log "Waiting for PostgreSQL to be ready ..."
  for i in $(seq 1 30); do
    if docker compose -f docker-compose.yml -f docker-compose.dev.yml exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" &>/dev/null; then
      log "PostgreSQL is ready"
      break
    fi
    if [ "$i" -eq 30 ]; then
      err "PostgreSQL failed to start within 30s"
    fi
    sleep 1
  done

  log "Waiting for Hasura to be ready ..."
  for i in $(seq 1 60); do
    if curl -sf "http://localhost:${HASURA_PORT}/healthz" &>/dev/null; then
      log "Hasura is ready at http://localhost:${HASURA_PORT}"
      break
    fi
    if [ "$i" -eq 60 ]; then
      err "Hasura failed to start within 60s"
    fi
    sleep 1
  done
}

##############################################################################
# 5. Apply Hasura metadata
##############################################################################
apply_hasura_metadata() {
  log "Applying Hasura metadata ..."

  if ! command -v hasura &>/dev/null; then
    log "Installing Hasura CLI ..."
    curl -fsSL https://graphql-engine-cdn.hasura.io/hasura-cli/v2.33.0/cli-hasura-darwin-arm64 -o /usr/local/bin/hasura 2>/dev/null \
      || curl -fsSL https://graphql-engine-cdn.hasura.io/hasura-cli/v2.33.0/cli-hasura-darwin-amd64 -o /usr/local/bin/hasura 2>/dev/null \
      || curl -L https://github.com/hasura/graphql-engine/raw/stable/cli/get.sh | bash
    chmod +x /usr/local/bin/hasura 2>/dev/null || true
  fi

  cd "${SCRIPT_DIR}/hasura"
  hasura metadata apply --endpoint "http://localhost:${HASURA_PORT}" --skip-update-check 2>&1 || {
    warn "Hasura metadata apply failed. Trying with curl API ..."
    apply_hasura_metadata_via_api
  }
  log "Hasura metadata applied"
}

apply_hasura_metadata_via_api() {
  log "Applying Hasura metadata via API (reload) ..."
  curl -s -X POST "http://localhost:${HASURA_PORT}/v1/metadata" \
    -H "Content-Type: application/json" \
    -d '{"type":"reload_metadata","args":{"reload_remote_schemas":true,"reload_sources":true}}' | head -c 500
  echo
}

##############################################################################
# 6. Download genesis (if needed)
##############################################################################
download_genesis() {
  GENESIS_FILE="${CALLISTO_HOME}/genesis.json"
  if [ -f "$GENESIS_FILE" ]; then
    log "Genesis file already exists at $GENESIS_FILE"
    return
  fi

  log "Downloading genesis from RPC ..."
  GENESIS_URL="https://sf-rpc-testnet.safrochain.com:443/genesis"

  if curl -sf "$GENESIS_URL" | python3 -c "import sys,json; json.dump(json.load(sys.stdin)['result']['genesis'], sys.stdout)" > "$GENESIS_FILE" 2>/dev/null; then
    log "Genesis downloaded to $GENESIS_FILE"
  else
    warn "Could not download genesis automatically. You may need to place it manually at $GENESIS_FILE"
  fi
}

##############################################################################
# 7. Configure Callisto
##############################################################################
configure_callisto() {
  log "Configuring callisto at $CALLISTO_HOME ..."
  mkdir -p "$CALLISTO_HOME"

  if [ ! -f "${CALLISTO_HOME}/config.yaml" ]; then
    err "Config not found at ${CALLISTO_HOME}/config.yaml — this should have been created by the repo"
  fi

  log "Callisto config ready at ${CALLISTO_HOME}/config.yaml"
  log "  - Modules: modules, messages, auth, bank, consensus, mint, distribution, staking, slashing, pricefeed, gov, feegrant, upgrade, wasm"
  log "  - Start height: 1"
  log "  - Target height: ${TARGET_HEIGHT}"
  log "  - RPC: https://sf-rpc-testnet.safrochain.com:443"
  log "  - gRPC: sf-grpc.testnet.safrochain.com:9090"
  log "  - Bech32 prefix: addr_safro"
  log "  - Actions port: ${CALLISTO_ACTIONS_PORT}"
}

##############################################################################
# 8. Start Callisto indexer
##############################################################################
start_callisto() {
  log "Starting callisto indexer ..."
  log "Indexing from block 1 to ${TARGET_HEIGHT} ..."
  log ""
  log "Command: ${SCRIPT_DIR}/build/callisto start --home ${CALLISTO_HOME}"
  log ""
  log "Starting in background. Logs will be written to ${SCRIPT_DIR}/callisto.log"
  log "Use 'tail -f ${SCRIPT_DIR}/callisto.log' to follow progress"
  log ""

  nohup "${SCRIPT_DIR}/build/callisto" start --home "$CALLISTO_HOME" \
    > "${SCRIPT_DIR}/callisto.log" 2>&1 &

  CALLISTO_PID=$!
  echo "$CALLISTO_PID" > "${SCRIPT_DIR}/callisto.pid"
  log "Callisto started with PID ${CALLISTO_PID}"
  log "To stop: kill \$(cat ${SCRIPT_DIR}/callisto.pid)"

  sleep 3
  if kill -0 "$CALLISTO_PID" 2>/dev/null; then
    log "Callisto is running"
  else
    err "Callisto failed to start. Check ${SCRIPT_DIR}/callisto.log"
  fi
}

##############################################################################
# Main
##############################################################################
main() {
  log "============================================="
  log "  Safrochain Callisto Indexer Setup"
  log "  Chain: safro-testnet-1"
  log "  Target height: ${TARGET_HEIGHT}"
  log "============================================="
  echo

  install_go
  echo
  install_safrochaind
  echo
  build_callisto
  echo
  start_docker_services
  echo
  apply_hasura_metadata
  echo
  download_genesis
  echo
  configure_callisto
  echo
  start_callisto
  echo

  log "============================================="
  log "  Setup complete!"
  log "============================================="
  log ""
  log "Services:"
  log "  PostgreSQL:       localhost:${POSTGRES_PORT}"
  log "  Hasura Console:   http://localhost:${HASURA_PORT}/console"
  log "  Hasura GraphQL:   http://localhost:${HASURA_PORT}/v1/graphql"
  log "  Callisto Actions: http://localhost:${CALLISTO_ACTIONS_PORT}"
  log "  Callisto Logs:    tail -f ${SCRIPT_DIR}/callisto.log"
  log ""
  log "Management:"
  log "  Stop callisto:    kill \$(cat ${SCRIPT_DIR}/callisto.pid)"
  log "  Stop infra:       cd ${SCRIPT_DIR} && docker compose -f docker-compose.yml -f docker-compose.dev.yml down"
  log "  Restart all:      cd ${SCRIPT_DIR} && bash setup.sh"
  log ""
}

main "$@"
