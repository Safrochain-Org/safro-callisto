#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[+] Stopping callisto ..."
if [ -f "${SCRIPT_DIR}/callisto.pid" ]; then
  PID=$(cat "${SCRIPT_DIR}/callisto.pid")
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    echo "[+] Callisto (PID $PID) stopped"
  else
    echo "[!] Callisto (PID $PID) was not running"
  fi
  rm -f "${SCRIPT_DIR}/callisto.pid"
else
  echo "[!] No callisto.pid found"
fi

echo "[+] Stopping docker services ..."
cd "$SCRIPT_DIR"
docker compose -f docker-compose.yml -f docker-compose.dev.yml down

echo "[+] All services stopped"
