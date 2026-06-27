#!/usr/bin/env bash
# Restore a full:50 node from a tzinit tar.lz4 backup (not octez snapshot import).
# Usage: ./scripts/import-full50.sh [mainnet|testnet]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

ARIA2_CONNECTIONS="${ARIA2_CONNECTIONS:-16}"
ARIA2_SPLIT="${ARIA2_SPLIT:-16}"

# shellcheck disable=SC1091
source "$ROOT/scripts/lib/network.sh"
load_network "${1:-testnet}"

if [[ "$HISTORY_MODE" != full:* ]]; then
  echo "[$NETWORK] HISTORY_MODE must be full:N (e.g. full:50), got: $HISTORY_MODE" >&2
  echo "Set TESTNET_HISTORY_MODE=full:50 (or mainnet equivalent) in .env" >&2
  exit 1
fi

if ! command -v lz4cat &>/dev/null; then
  echo "lz4 is required. Install with: apt install lz4" >&2
  exit 1
fi

ensure_data_dirs
mkdir -p "$(dirname "$FULL50_FILE")"

echo "[$NETWORK] Stopping node before full:50 restore..."
"${COMPOSE[@]}" stop "$COMPOSE_SERVICE_NODE" 2>/dev/null || true
rm -f "$NODE_DATA_DIR/data/lock"

download_backup() {
  local url="$1" dest="$2"

  if [[ -s "$dest" ]]; then
    echo "[$NETWORK] Using existing backup: $dest"
    return 0
  fi

  if ! command -v aria2c &>/dev/null; then
    echo "aria2c is required but not installed. Install with: apt install aria2" >&2
    exit 1
  fi

  local dest_dir dest_name
  dest_dir="$(cd "$(dirname "$dest")" && pwd)"
  dest_name="$(basename "$dest")"

  echo "[$NETWORK] Downloading full:50 backup with aria2c from $url ..."
  aria2c \
    -d "$dest_dir" \
    -o "$dest_name" \
    --continue=true \
    --max-connection-per-server="$ARIA2_CONNECTIONS" \
    --split="$ARIA2_SPLIT" \
    --min-split-size=1M \
    --file-allocation=none \
    --console-log-level=notice \
    "$url"
}

download_backup "$FULL50_URL" "$FULL50_FILE"

echo "[$NETWORK] Removing old chain data (keeping config.json and identity.json)..."
rm -rf "$NODE_DATA_DIR/data/context" "$NODE_DATA_DIR/data/store" "$NODE_DATA_DIR/data/daily_logs"
# Remove misplaced top-level dirs from a prior extract into NODE_DATA_DIR
rm -rf "$NODE_DATA_DIR/context" "$NODE_DATA_DIR/store" "$NODE_DATA_DIR/daily_logs"
rm -f "$NODE_DATA_DIR/version.json"

mkdir -p "$NODE_DATA_DIR/data"

echo "[$NETWORK] Extracting full:50 backup into $(basename "$NODE_DATA_DIR")/data/ ..."
lz4cat "$FULL50_FILE" | tar -xf - -C "$NODE_DATA_DIR/data"

echo "[$NETWORK] Setting history mode to $HISTORY_MODE ..."
"${COMPOSE[@]}" run --rm --no-deps --entrypoint octez-node "$COMPOSE_SERVICE_NODE" \
  config update --data-dir /var/run/tezos/node/data --history-mode "$HISTORY_MODE"

ensure_data_dirs

echo "[$NETWORK] full:50 restore finished. Start with: ./scripts/up.sh $NETWORK"
