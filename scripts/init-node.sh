#!/usr/bin/env bash
# Initialize node config for mainnet or testnet (Shadownet).
# Usage: ./scripts/init-node.sh [mainnet|testnet]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

# shellcheck disable=SC1091
source "$ROOT/scripts/lib/network.sh"
load_network "${1:-mainnet}"

ensure_data_dirs

CONFIG_PATH="$NODE_DATA_DIR/data/config.json"
if [[ -f "$CONFIG_PATH" ]]; then
  echo "[$NETWORK] Node config already exists at $CONFIG_PATH — skipping init."
  echo "To re-init, remove the data directory for this network."
  exit 0
fi

echo "[$NETWORK] Initializing node (history-mode=$HISTORY_MODE)..."
"${COMPOSE[@]}" --profile setup run --rm "$COMPOSE_SERVICE_INIT"

echo "[$NETWORK] Config written. Next: ./scripts/import-snapshot.sh $NETWORK (recommended) then start the node."
