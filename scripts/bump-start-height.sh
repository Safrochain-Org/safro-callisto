#!/usr/bin/env bash
# Prints a suggested start_height for a *pruned* public RPC (latest - offset).
# Does NOT modify .callisto/config.yaml unless you set UPDATE_START_HEIGHT=1.
#
# Keep parsing.start_height in config.yaml (e.g. 8000000) for archive nodes; run this
# only when you intentionally want to patch the file for a pruned endpoint.
#
# Usage:
#   ./scripts/bump-start-height.sh                    # print only
#   UPDATE_START_HEIGHT=1 ./scripts/bump-start-height.sh   # write config
#   RPC_URL=https://node:443 START_HEIGHT_OFFSET=55 UPDATE_START_HEIGHT=1 ./scripts/bump-start-height.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="${ROOT}/.callisto/config.yaml"
RPC="${RPC_URL:-https://sf-rpc-testnet.safrochain.com:443}"
OFFSET="${START_HEIGHT_OFFSET:-1000000}"

latest="$(curl -sSf "${RPC}/status" | jq -r '.result.sync_info.latest_block_height')"
start=$((latest - OFFSET))

if [[ "$start" -lt 0 ]]; then
  echo "Computed start_height would be $start; refusing."
  exit 1
fi

echo "RPC latest_block_height=${latest}  suggested start_height (latest - ${OFFSET})=${start}"

if [[ "${UPDATE_START_HEIGHT:-0}" != "1" ]]; then
  echo "Config unchanged. To write ${CFG}, run: UPDATE_START_HEIGHT=1 $0"
  exit 0
fi

if [[ "$(uname)" == Darwin ]]; then
  sed -i '' "s/^  start_height: .*/  start_height: ${start}/" "${CFG}"
else
  sed -i "s/^  start_height: .*/  start_height: ${start}/" "${CFG}"
fi

echo "Updated ${CFG}: start_height=${start}"
