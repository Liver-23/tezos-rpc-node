# Tezos mainnet RPC node (Docker)

Docker setup for an [Octez](https://octez.tezos.com/docs/introduction/howtoget.html) mainnet node that exposes the Tezos node REST RPC on port **8732**, matching the API collections in [`TEZOSSpec.json`](TEZOSSpec.json) (Lava protocol spec).

| Collection | Interface | HTTP | APIs |
|------------|-----------|------|------|
| GET | `rest` | GET | 180 endpoints |
| POST | `rest` | POST | 32 endpoints |

The spec expects mainnet chain id `NetXdQprcVkpaWU` and optional **archive** extension for queries more than ~28,000 blocks behind head.

## Requirements

- Docker Engine + Docker Compose v2
- [aria2](https://aria2.github.io/) for snapshot downloads (`apt install aria2`)
- `node_data/` and `client_data/` must be writable by container user **1000** (`tezos`); `init-node.sh` sets this automatically
- **Disk**: ~100 GB+ SSD for `rolling`/`full`; **2 TB+** for `archive`
- **RAM**: 8 GB minimum (16 GB recommended)
- Open **9732/tcp** (P2P) if peers must reach this host

## Quick start

```bash
cd /root/.tezos
cp .env.example .env

# 1) Initialize node config (mainnet, RPC on [::]:8732, allow-all-rpc)
./scripts/init-node.sh

# 2) Import a snapshot (strongly recommended)
./scripts/import-snapshot.sh

# 3) Run the node
docker compose up -d

# 4) Wait until bootstrapped
docker compose exec node octez-client -E http://127.0.0.1:8732 bootstrapped

# 5) Verify RPC matches TEZOSSpec
./scripts/verify-spec-apis.sh
```

RPC base URL: `http://127.0.0.1:8732` (e.g. `GET /version`, `GET /chains/main/blocks/head/header`).

## History modes vs TEZOSSpec

| Mode | Use case | TEZOSSpec |
|------|----------|-----------|
| `full` (default) | Balanced disk; recent + pruning window | Passes default **pruning** verification (28k blocks) |
| `rolling` | Smallest disk | May fail pruning checks for old blocks |
| `archive` | Full historical state | Required for **archive** extension (28k+ lookback) |

Archive mode:

```bash
# In .env: HISTORY_MODE=archive and SNAPSHOT_URL_ARCHIVE=...
docker compose -f docker-compose.yml -f docker-compose.archive.yml --profile setup run --rm init
./scripts/import-snapshot.sh
docker compose -f docker-compose.yml -f docker-compose.archive.yml up -d
```

## Configuration

Copy [`.env.example`](.env.example) to `.env`:

- `OCTEZ_IMAGE` — default `tezos/tezos-bare:latest`
- `HISTORY_MODE` — `full`, `rolling`, or `archive`
- `RPC_PORT` / `P2P_PORT` — host port mappings
- `SNAPSHOT_URL` — snapshot download URL ([tzinit](https://snapshots.tzinit.org/), [xtz-shots](https://xtz-shots.io/), etc.)
- `ARIA2_CONNECTIONS` / `ARIA2_SPLIT` — parallel connections for `aria2c` (default 16)

Node init sets:

- `--network mainnet`
- `--rpc-addr '[::]:8732'`
- `--allow-all-rpc '[::]:8732'` (required for POST injection/helpers in the spec)

## Operations

```bash
# Logs
docker compose logs -f node

# Stop / start
docker compose stop node
docker compose start node

# Upgrade storage after image bump
docker compose stop node
docker compose run --rm node octez-node upgrade storage --data-dir /var/run/tezos/node/data
docker compose up -d node
```

## Security

This configuration exposes the **full** node RPC (`--allow-all-rpc`). Do not publish port 8732 to the public internet without a reverse proxy, firewall, and rate limits. Prefer binding RPC to localhost and tunneling for production.

## References

- [Developing on Tezos](https://docs.tezos.com/developing)
- [Installing Octez (Docker)](https://octez.tezos.com/docs/introduction/howtoget.html#using-docker-images)
- [Run an Octez node](https://docs.tezos.com/tutorials/join-dal-baker/run-node)
- [History modes](https://octez.tezos.com/docs/user/history_modes.html)
- [Snapshots](https://octez.tezos.com/docs/user/snapshots.html)
