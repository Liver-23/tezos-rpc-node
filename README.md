# Tezos mainnet & testnet RPC nodes (Docker)

Docker setup for [Octez](https://octez.tezos.com/docs/introduction/howtoget.html) **mainnet** (default) and **Shadownet testnet** (`--profile testnet`) nodes. Each network uses separate data directories and host ports so they can run in parallel without mixing chain state.

Mainnet exposes REST RPC on port **8732**, matching the API collections in [`TEZOSSpec.json`](TEZOSSpec.json) (Lava protocol spec).

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
- Open **9732/tcp** (mainnet P2P) and/or **9733/tcp** (testnet P2P) if peers must reach this host; RPC defaults to **127.0.0.1:8732** (mainnet) and **127.0.0.1:8733** (testnet)

## Quick start (mainnet)

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
./scripts/verify-spec-apis.sh   # skips long-poll /monitor/* APIs from the spec
```

RPC base URL: `http://127.0.0.1:8732` (e.g. `GET /version`, `GET /chains/main/blocks/head/header`).

## Quick start (testnet / Shadownet)

Testnet uses the `testnet` compose profile, separate `testnet_node_data/` / `testnet_client_data/` dirs, and host ports **8733** (RPC) / **9733** (P2P).

```bash
cd /root/.tezos
cp .env.example .env   # if not done yet

# 1) Initialize testnet config
./scripts/init-node.sh testnet

# 2) Import a snapshot (strongly recommended)
#    rolling/full: ./scripts/import-snapshot.sh testnet
#    full:50 (TEZOSSpec 28k-block pruning): set TESTNET_HISTORY_MODE=full:50 then:
./scripts/import-snapshot.sh testnet

# 3) Run testnet only
./scripts/up.sh testnet
# or: docker compose --profile testnet up -d testnet-node

# 4) Wait until bootstrapped
docker compose exec testnet-node octez-client -E http://127.0.0.1:8732 bootstrapped
```

Testnet RPC from the host: `http://127.0.0.1:8733` (chain id `NetXsqzbfFenSTS`).

### Testnet history mode vs TEZOSSpec

| Mode | Disk (Shadownet) | TEZOSSpec pruning (28k blocks) |
|------|------------------|----------------------------------|
| `rolling` | ~1 GB | Fails — blocks pruned |
| `full` | ~20 GB | May fail — only ~2 cycles of context (~16k blocks) |
| `full:50` | ~80 GB | Passes — 50+ cycles of context (~400k+ blocks) |

Restore `full:50` from tzinit tar.lz4 (not snapshot import):

```bash
# In .env: TESTNET_HISTORY_MODE=full:50
docker compose --profile testnet stop testnet-node
./scripts/import-full50.sh testnet
./scripts/up.sh testnet
```

## Running mainnet and testnet together

| Command | What starts |
|---------|-------------|
| `docker compose up -d` | Mainnet only (unchanged) |
| `docker compose --profile testnet up -d testnet-node` | Testnet only |
| `docker compose --profile testnet up -d` | Both mainnet and testnet |
| `./scripts/up.sh both` | Both mainnet and testnet |

To always start both when you run `docker compose up -d`, set in `.env`:

```bash
COMPOSE_PROFILES=testnet
```

| Network | Container | Data dirs | RPC (host) | P2P (host) | Chain ID |
|---------|-----------|-----------|------------|------------|----------|
| Mainnet | `tezos-mainnet-rpc` | `node_data/`, `client_data/` | `127.0.0.1:8732` | `9732` | `NetXdQprcVkpaWU` |
| Shadownet | `tezos-testnet-rpc` | `testnet_node_data/`, `testnet_client_data/` | `127.0.0.1:8733` | `9733` | `NetXsqzbfFenSTS` |

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
- `HISTORY_MODE` — mainnet: `full`, `rolling`, or `archive`
- `RPC_PORT` / `P2P_PORT` — mainnet host port mappings
- `TESTNET_*` — testnet ports, snapshot URL, chain id (see `.env.example`)
- `COMPOSE_PROFILES=testnet` — auto-enable testnet profile with every `docker compose` invocation
- `SNAPSHOT_URL` — mainnet snapshot download URL ([tzinit](https://snapshots.tzinit.org/), [xtz-shots](https://xtz-shots.io/), etc.)
- `TESTNET_SNAPSHOT_URL` — Shadownet snapshot (default `https://snapshots.tzinit.org/shadownet/rolling`)
- `ARIA2_CONNECTIONS` / `ARIA2_SPLIT` — parallel connections for `aria2c` (default 16)

Node init sets:

- `--network mainnet`
- `--rpc-addr '[::]:8732'`
- `--allow-all-rpc '[::]:8732'` (required for POST injection/helpers in the spec)

## Re-import after corruption (`Inconsistent_store`)

Stop the node, then re-import (the script uses Octez `--force` to remove `context`, `store`, and `daily_logs`):

```bash
docker compose stop node
./scripts/import-snapshot.sh mainnet
docker compose up -d
```

For testnet: `docker compose --profile testnet stop testnet-node` then `./scripts/import-snapshot.sh testnet`.

Keep `config.json` and `identity.json`; only chain data is replaced.

## Operations

```bash
# Logs
docker compose logs -f node
docker compose --profile testnet logs -f testnet-node

# Stop / start
docker compose stop node
docker compose start node
docker compose --profile testnet stop testnet-node
docker compose --profile testnet start testnet-node

# Upgrade storage after image bump
docker compose stop node
docker compose run --rm node octez-node upgrade storage --data-dir /var/run/tezos/node/data
docker compose up -d node
```

## Security

- **RPC** is published on `127.0.0.1:8732` only (set `RPC_BIND` in `.env` to change).
- **`--private-mode`** reduces P2P gossip exposure (RPC-only operation).
- **`--allow-all-rpc`** is still enabled inside the container for TEZOSSpec POST APIs; put a reverse proxy in front if you expose RPC externally.
- Tezos uses ports **8732/9732**, not Substrate **30333/30334** — unrelated to Polkadot netscan reports.

## References

- [Developing on Tezos](https://docs.tezos.com/developing)
- [Installing Octez (Docker)](https://octez.tezos.com/docs/introduction/howtoget.html#using-docker-images)
- [Run an Octez node](https://docs.tezos.com/tutorials/join-dal-baker/run-node)
- [History modes](https://octez.tezos.com/docs/user/history_modes.html)
- [Snapshots](https://octez.tezos.com/docs/user/snapshots.html)
