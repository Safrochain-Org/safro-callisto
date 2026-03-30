# Explorer GraphQL documents (Hasura)

Single file: **`explorer.graphql`** — fragments plus operations for slim lists, batched txs, height-based counts, blocks, charts, validators, governance, messages, search, and subscriptions.

Copy this file into your explorer app (or point `graphql-codegen` at it) and replace string-built chart/query strings in `api.ts` with imports.

## Checklist (permissions & limits)

| Area | Notes |
|------|--------|
| **Role** | Metadata in this repo uses **`viewer`** for table permissions. If the app uses **`anonymous`**, mirror the same `select` + `allow_aggregations` (where needed) for `transaction`, `block`, `proposal`, etc. |
| **Row limits** | Hasura `limit: 100` is set on several tables for `viewer`. Keep `limit`/`offset` within that cap or raise metadata limits for list screens. |
| **`_in` batch size** | `GetTransactionsByHashes` — keep hash list size reasonable (Postgres `IN (...)` / Hasura query size). Batch in chunks (e.g. 50–200) if needed. |
| **Height vs time** | Use **`GetTransactionCountBetweenByHeight`** when `block.timestamp` filters misbehave on partitions; optionally pair with **`ChartBucketHeightBounds`** + block height lookup. |
| **Subscriptions** | Require Hasura websocket URL + CORS; **`OnLatestTransactionsSummary`** should use the same fields as list rows to avoid over-fetch. |
| **CosmWasm** | No separate contract tables — use **`GetMessagesByType`** with full `type` strings (e.g. wasm execute paths). |

## Global search

There is no single server-side “resolve search string” operation. Use **`SearchTransactionByHash`**, **`SearchBlockByHeight`**, **`SearchBlockByHashPrefix`**, and **`SearchAccountByAddress`** in parallel from the client (with Apollo `skip`), or route by search pattern.

## Validation

Operations were smoke-tested against `https://sf-indexer-testnet.safrochain.com/v1/graphql` for shape compatibility with this repo’s Hasura metadata.
