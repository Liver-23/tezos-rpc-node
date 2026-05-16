#!/usr/bin/env bash
# Initialize mainnet node config for RPC serving (TEZOSSpec REST GET/POST APIs).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

COMPOSE=(docker compose -f docker-compose.yml)
if [[ "${HISTORY_MODE:-full}" == "archive" ]]; then
  COMPOSE+=(-f docker-compose.archive.yml)
fi

TEZOS_UID="${TEZOS_UID:-1000}"
TEZOS_GID="${TEZOS_GID:-1000}"

mkdir -p "$ROOT/node_data" "$ROOT/client_data"
# tezos/tezos-bare runs as uid 1000; bind mounts must be writable by that user
if [[ "$(stat -c '%u:%g' "$ROOT/node_data")" != "${TEZOS_UID}:${TEZOS_GID}" ]]; then
  echo "Setting ownership of node_data/ and client_data/ to ${TEZOS_UID}:${TEZOS_GID} ..."
  chown -R "${TEZOS_UID}:${TEZOS_GID}" "$ROOT/node_data" "$ROOT/client_data"
fi

CONFIG_PATH="$ROOT/node_data/data/config.json"
if [[ -f "$CONFIG_PATH" ]]; then
  echo "Node config already exists at $CONFIG_PATH — skipping init."
  echo "To re-init, remove the node_data volume: docker compose down -v"
  exit 0
fi

echo "Initializing mainnet node (history-mode=${HISTORY_MODE:-full})..."
"${COMPOSE[@]}" --profile setup run --rm init

echo "Config written. Next: ./scripts/import-snapshot.sh (recommended) then: docker compose up -d"
