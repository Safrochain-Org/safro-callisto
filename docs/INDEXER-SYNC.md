# Indexer sync notes (Safro Callisto)

## Quick reset + run

From `safro-callisto/`:

```bash
./scripts/dev-stack.sh all
./scripts/dev-stack.sh logs   # optional: follow Callisto output
```

- **`all`** = stop Callisto → `docker compose down -v` → `up -d` → wait for Postgres/Hasura → `hasura metadata apply` → Callisto in **background** (`logs/callisto-sync.log`).
- **`start_height`** is whatever you set in `.callisto/config.yaml` (default **0** needs **archive** RPC/gRPC if the node is pruned; see below).

Other commands: `./scripts/dev-stack.sh help` · verify prerequisites: `./scripts/dev-stack.sh check`

## Public RPC pruning

The testnet RPC (`https://sf-rpc-testnet.safrochain.com:443`) may keep only a **short** window of queryable IAVL state. If `parsing.start_height` is older than that window, gRPC queries fail with:

`version mismatch on immutable IAVL tree; version does not exist`

**Replaying from genesis (`start_height: 0`) or any height outside the retention window requires an archive gRPC/RPC** pointing `node.config.rpc` and `node.config.grpc` at that archive service.

## `start_height` in `.callisto/config.yaml`

Default in-repo is **0** (full history). That requires **archive** RPC/gRPC on the endpoints in `.callisto/config.yaml`; on a pruned public node, raise `start_height` or switch to archive URLs.

`./scripts/bump-start-height.sh` **only prints** a suggested `latest - offset` for pruned RPC. It does **not** edit the config unless you run:

```bash
UPDATE_START_HEIGHT=1 ./scripts/bump-start-height.sh
```

Optional: `RPC_URL=... START_HEIGHT_OFFSET=40 UPDATE_START_HEIGHT=1 ./scripts/bump-start-height.sh`

Then:

```bash
docker compose up -d
# Hasura CLI needs hasura/config.yaml as cwd (or use --project hasura from safro-callisto root):
./scripts/hasura-metadata-apply.sh
# Or: (cd hasura && hasura metadata apply --endpoint http://localhost:8080)
# Or from safro-callisto root: hasura metadata apply --endpoint http://localhost:8080 --project hasura
./build/callisto start --home .callisto
```

### Hasura env var (Bash/zsh vs Fish)

Use a **separate line** for the secret—do not put `# comments` on the same line as `export` in **Fish** (you can get `export: not valid in this context: docker-compose`).

**Bash / zsh:**

```bash
export HASURA_GRAPHQL_ADMIN_SECRET=myadminsecretkey
```

**Fish:**

```fish
set -x HASURA_GRAPHQL_ADMIN_SECRET myadminsecretkey
```

Easiest: run **`./scripts/hasura-metadata-apply.sh`** from `safro-callisto` (no manual `export`).

## Fixes applied in this fork

- **Gov genesis**: Strips gov JSON keys added in newer SDKs (e.g. `constitution`, extra `params` fields) before codec decode.
- **Wasm txs**: Registers `CosmWasm/wasmd` `AppModuleBasic` so `MsgExecuteContract` (and related) unpack in Juno’s tx decoder.
- **Staking voting power / status**: Avoids zero-value rows when skipping unknown validators; dedupes batch inserts so PostgreSQL `ON CONFLICT` is not hit twice in one statement.


./scripts/dev-stack.sh all	Stops Callisto → docker compose down -v (drops DB volume) → up -d → waits for Postgres & Hasura → hasura metadata apply → starts Callisto in the background and appends logs/callisto-sync.log
./scripts/dev-stack.sh reset	Same as above without starting Callisto
./scripts/dev-stack.sh up	docker compose up -d (keeps data) + Hasura apply
./scripts/dev-stack.sh stop	Stops Callisto only (Docker keeps running)
./scripts/dev-stack.sh build	make build
./scripts/dev-stack.sh start	Foreground Callisto (builds if build/callisto is missing)
./scripts/dev-stack.sh start-bg	Background Callisto + log file
./scripts/dev-stack.sh logs	tail -f logs/callisto-sync.log
./scripts/dev-stack.sh help	Short usage
