# Callisto
[![GitHub Workflow Status](https://img.shields.io/github/workflow/status/forbole/bdjuno/Tests)](https://github.com/forbole/bdjuno/actions?query=workflow%3ATests)
[![Go Report Card](https://goreportcard.com/badge/github.com/forbole/bdjuno)](https://goreportcard.com/report/github.com/forbole/bdjuno)
![Codecov branch](https://img.shields.io/codecov/c/github/forbole/bdjuno/cosmos/v0.40.x)

Callisto (formerly BDJuno) is the [Juno](https://github.com/forbole/juno) implementation
for [Big Dipper](https://github.com/forbole/big-dipper).

It extends the custom Juno behavior by adding different handlers and custom operations to make it easier for Big Dipper
showing the data inside the UI.

All the chains' data that are queried from the RPC and gRPC endpoints are stored inside
a [PostgreSQL](https://www.postgresql.org/) database on top of which [GraphQL](https://graphql.org/) APIs can then be
created using [Hasura](https://hasura.io/).

## Local stack (Safro fork)

The repo includes **`.callisto/config.yaml`** (defaults match `docker-compose` Postgres on `localhost:5434`). Edit RPC/gRPC, `database.url`, and `parsing.start_height` as needed (see `docs/INDEXER-SYNC.md`). You can copy **`.callisto/config.yaml.example`** if you want a backup before editing.

**Before the first `callisto start`**, create tables with **`./scripts/migrate-db.sh`** (loads `POSTGRES_*` from `.env`; defaults to `127.0.0.1:5434` for Docker). Without this, `callisto` exits with `relation "modules" does not exist`.

From this directory:

| Command | What it does |
|--------|----------------|
| `./scripts/dev-stack.sh all` | Stop Callisto → `docker compose … down -v` → `up -d` (uses `docker-compose.yml` + `docker-compose.dev.yml`) → wait Postgres & Hasura → Hasura metadata apply → Callisto **in background** (`logs/callisto-sync.log`) |
| `./scripts/dev-stack.sh reset` | Same as `all` but does **not** start Callisto |
| `./scripts/dev-stack.sh up` | `docker compose … up -d` (keeps data) → wait → Hasura metadata apply |
| `./scripts/dev-stack.sh stop` | Stop Callisto only (Docker keeps running) |
| `./scripts/dev-stack.sh build` | `make build` |
| `./scripts/dev-stack.sh start` | Callisto in **foreground** (builds if `build/callisto` missing) |
| `./scripts/dev-stack.sh start-bg` | Callisto in **background** + log file |
| `./scripts/dev-stack.sh logs` | `tail -f logs/callisto-sync.log` |
| `./scripts/dev-stack.sh check` | Verify Docker daemon, `docker compose`, `curl`, `hasura` CLI, compose/hasura paths, `.callisto/config.yaml`, and Go/`make` or existing binary |
| `./scripts/dev-stack.sh help` | Short usage |

Requires: **Docker** (daemon running), **`docker compose` v2**, **`curl`**, **[Hasura CLI](https://hasura.io/docs/latest/hasura-cli/install-hasura-cli/)**, **Go** + **make** (to build Callisto, or a prebuilt `build/callisto`). Set `SKIP_DEV_STACK_CHECKS=1` only if you must bypass checks.

See `docs/INDEXER-SYNC.md` for RPC pruning / `start_height` and archive nodes.

**Production server** (Docker + systemd + Nginx, GraphQL hostname): `docs/DEPLOY-SERVER.md`.

## Usage
To know how to setup and run Callisto, please refer to
the [docs website](https://docs.bigdipper.live/cosmos-based/parser/overview/).

## Testing
If you want to test the code, you can do so by running

```shell
$ make test-unit
```

**Note**: Requires [Docker](https://docker.com).

This will:
1. Create a Docker container running a PostgreSQL database.
2. Run all the tests using that database as support.


pkill -f 'callisto start'
docker compose down
./scripts/reset-db.sh
./build/callisto parse genesis-file --home .callisto --genesis-file-path .callisto/genesis.json
docker compose --env-file .env up -d
sleep 5
cd hasura && hasura metadata apply --endpoint http://127.0.0.1:8080 --admin-secret myadminsecretkey && cd ..
mkdir -p logs
nohup ./build/callisto start --home .callisto >> logs/callisto-sync.log 2>&1 &
tail -f logs/callisto-sync.log


