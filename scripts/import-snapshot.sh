#!/usr/bin/env bash
# Download (optional) and import a mainnet snapshot for faster bootstrap.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

TEZOS_UID="${TEZOS_UID:-1000}"
TEZOS_GID="${TEZOS_GID:-1000}"

SNAPSHOT_FILE="${SNAPSHOT_FILE:-./snapshots/mainnet.snapshot}"
SNAPSHOT_URL="${SNAPSHOT_URL:-https://snapshots.tzinit.org/mainnet/rolling}"
ARIA2_CONNECTIONS="${ARIA2_CONNECTIONS:-16}"
ARIA2_SPLIT="${ARIA2_SPLIT:-16}"

if [[ "${HISTORY_MODE:-full}" == "archive" ]]; then
  SNAPSHOT_URL="${SNAPSHOT_URL_ARCHIVE:-$SNAPSHOT_URL}"
fi

mkdir -p "$(dirname "$SNAPSHOT_FILE")" node_data client_data
chown -R "${TEZOS_UID}:${TEZOS_GID}" node_data client_data 2>/dev/null || true

download_snapshot() {
  local url="$1" dest="$2"

  if [[ -s "$dest" ]]; then
    echo "Using existing snapshot: $dest"
    return 0
  fi

  if ! command -v aria2c &>/dev/null; then
    echo "aria2c is required but not installed. Install with: apt install aria2" >&2
    exit 1
  fi

  local dest_dir dest_name
  dest_dir="$(cd "$(dirname "$dest")" && pwd)"
  dest_name="$(basename "$dest")"

  echo "Downloading snapshot with aria2c from $url ..."
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

COMPOSE=(docker compose -f docker-compose.yml)
if [[ "${HISTORY_MODE:-full}" == "archive" ]]; then
  COMPOSE+=(-f docker-compose.archive.yml)
fi

export SNAPSHOT_FILE
echo "Importing snapshot (this can take a long time)..."
"${COMPOSE[@]}" --profile setup run --rm import-snapshot

echo "Import finished. Start the node: docker compose up -d"
