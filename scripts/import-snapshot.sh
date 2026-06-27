#!/usr/bin/env bash
# Download (optional) and import a snapshot for mainnet or testnet (Shadownet).
# Usage: ./scripts/import-snapshot.sh [mainnet|testnet]
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
load_network "${1:-mainnet}"

ensure_data_dirs
mkdir -p "$(dirname "$SNAPSHOT_FILE")"

echo "[$NETWORK] Stopping node before snapshot import..."
"${COMPOSE[@]}" stop "$COMPOSE_SERVICE_NODE" 2>/dev/null || true
rm -f "$NODE_DATA_DIR/data/lock"

download_snapshot() {
  local url="$1" dest="$2"

  if [[ -s "$dest" ]]; then
    echo "[$NETWORK] Using existing snapshot: $dest"
    return 0
  fi

  if ! command -v aria2c &>/dev/null; then
    echo "aria2c is required but not installed. Install with: apt install aria2" >&2
    exit 1
  fi

  local dest_dir dest_name
  dest_dir="$(cd "$(dirname "$dest")" && pwd)"
  dest_name="$(basename "$dest")"

  echo "[$NETWORK] Downloading snapshot with aria2c from $url ..."
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

download_snapshot "$SNAPSHOT_URL" "$SNAPSHOT_FILE"

if [[ "$NETWORK" == "mainnet" ]]; then
  export SNAPSHOT_FILE
else
  export TESTNET_SNAPSHOT_FILE="$SNAPSHOT_FILE"
fi

echo "[$NETWORK] Importing snapshot (--force cleans context, store, daily_logs)..."
echo "[$NETWORK] This can take a long time."
"${COMPOSE[@]}" --profile setup run --rm "$COMPOSE_SERVICE_IMPORT"

echo "[$NETWORK] Import finished. Start with: ./scripts/up.sh $NETWORK"
