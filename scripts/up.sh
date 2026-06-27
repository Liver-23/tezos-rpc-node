#!/usr/bin/env bash
# Start mainnet, testnet, or both.
# Usage:
#   ./scripts/up.sh mainnet   # mainnet only (same as docker compose up -d)
#   ./scripts/up.sh testnet   # testnet only
#   ./scripts/up.sh both      # mainnet + testnet
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

target="${1:-mainnet}"

case "$target" in
  mainnet)
    docker compose up -d node
    ;;
  testnet)
    docker compose --profile testnet up -d testnet-node
    ;;
  both)
    docker compose --profile testnet up -d
    ;;
  *)
    echo "Usage: $0 [mainnet|testnet|both]" >&2
    exit 1
    ;;
esac

docker compose ps
