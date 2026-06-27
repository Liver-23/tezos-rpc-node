#!/usr/bin/env bash
# Shared network selection for mainnet vs testnet (Shadownet) compose workflows.
set -euo pipefail

resolve_network() {
  local net="${1:-mainnet}"
  case "$net" in
    mainnet | testnet) echo "$net" ;;
    *)
      echo "Unknown network: $net (expected mainnet or testnet)" >&2
      exit 1
      ;;
  esac
}

load_network() {
  local net
  net="$(resolve_network "${1:-mainnet}")"

  NETWORK="$net"
  ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

  COMPOSE=(docker compose -f "$ROOT/docker-compose.yml")

  case "$net" in
    mainnet)
      NODE_DATA_DIR="$ROOT/node_data"
      CLIENT_DATA_DIR="$ROOT/client_data"
      COMPOSE_SERVICE_NODE=node
      COMPOSE_SERVICE_INIT=init
      COMPOSE_SERVICE_IMPORT=import-snapshot
      HISTORY_MODE="${HISTORY_MODE:-full}"
      SNAPSHOT_FILE="${SNAPSHOT_FILE:-./snapshots/mainnet.snapshot}"
      SNAPSHOT_URL="${SNAPSHOT_URL:-https://snapshots.tzinit.org/mainnet/rolling}"
      if [[ "$HISTORY_MODE" == "archive" ]]; then
        SNAPSHOT_URL="${SNAPSHOT_URL_ARCHIVE:-$SNAPSHOT_URL}"
        COMPOSE+=(-f "$ROOT/docker-compose.archive.yml")
      fi
      RPC_URL="${RPC_URL:-http://127.0.0.1:${RPC_PORT:-8732}}"
      CHAIN_ID="${MAINNET_CHAIN_ID:-NetXdQprcVkpaWU}"
      ;;
    testnet)
      COMPOSE+=(--profile testnet)
      NODE_DATA_DIR="$ROOT/testnet_node_data"
      CLIENT_DATA_DIR="$ROOT/testnet_client_data"
      COMPOSE_SERVICE_NODE=testnet-node
      COMPOSE_SERVICE_INIT=testnet-init
      COMPOSE_SERVICE_IMPORT=testnet-import-snapshot
      HISTORY_MODE="${TESTNET_HISTORY_MODE:-rolling}"
      SNAPSHOT_FILE="${TESTNET_SNAPSHOT_FILE:-./snapshots/testnet.snapshot}"
      SNAPSHOT_URL="${TESTNET_SNAPSHOT_URL:-https://snapshots.tzinit.org/shadownet/rolling}"
      FULL50_FILE="${TESTNET_FULL50_FILE:-./snapshots/testnet-full50.tar.lz4}"
      FULL50_URL="${TESTNET_FULL50_URL:-https://snapshots.tzinit.org/shadownet/full50.tar.lz4}"
      RPC_URL="${TESTNET_RPC_URL:-http://127.0.0.1:${TESTNET_RPC_PORT:-8733}}"
      CHAIN_ID="${TESTNET_CHAIN_ID:-NetXsqzbfFenSTS}"
      ;;
  esac
}

ensure_data_dirs() {
  local uid="${TEZOS_UID:-1000}"
  local gid="${TEZOS_GID:-1000}"

  mkdir -p "$NODE_DATA_DIR" "$CLIENT_DATA_DIR"
  if [[ "$(stat -c '%u:%g' "$NODE_DATA_DIR")" != "${uid}:${gid}" ]]; then
    echo "Setting ownership of $(basename "$NODE_DATA_DIR")/ and $(basename "$CLIENT_DATA_DIR")/ to ${uid}:${gid} ..."
    chown -R "${uid}:${gid}" "$NODE_DATA_DIR" "$CLIENT_DATA_DIR"
  fi
}
