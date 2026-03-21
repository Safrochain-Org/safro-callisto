# Production server deployment (Callisto + Postgres + Hasura + Nginx)

This guide assumes a **Linux server** (Ubuntu 22.04 LTS is a common choice), a dedicated deploy user, **Docker Engine + Compose v2**, **Nginx**, and TLS via **Let’s Encrypt**. GraphQL will be served at **`https://sf-indexer-testnet.safrochain.com/v1/graphql`** (adjust DNS and names to match your environment).

---

## 1. Architecture (what runs where)

| Component | How it runs | Listens |
|-----------|-------------|---------|
| PostgreSQL | Docker (`safro-postgres`) | `127.0.0.1:5434` → container `5432` (production overlay) |
| Hasura | Docker (`safro-hasura`) | `127.0.0.1:8080` (production overlay) |
| Callisto | **systemd** on the host | RPC/gRPC to chain; DB to `127.0.0.1:5434`; actions `127.0.0.1:3001` |
| Nginx | **systemd** | Public `80`/`443` → reverse proxy to Hasura |

Do **not** expose Postgres or Hasura directly to the internet. Only Nginx (and SSH) should be public.

---

## 2. Server baseline

1. **Create a non-root user** (e.g. `deploy`) with `sudo`.
2. **Install packages** (Debian/Ubuntu examples):

   ```bash
   sudo apt update && sudo apt install -y git curl jq nginx ufw
   ```

3. **Firewall** — allow SSH, HTTP, HTTPS; default deny incoming:

   ```bash
   sudo ufw allow OpenSSH
   sudo ufw allow 'Nginx Full'
   sudo ufw enable
   ```

4. **Install Docker** (official [Docker Engine docs](https://docs.docker.com/engine/install/)) and add `deploy` to the `docker` group:

   ```bash
   sudo usermod -aG docker deploy
   # log out and back in
   docker compose version
   ```

5. **DNS**: Point **`sf-indexer-testnet.safrochain.com`** (A/AAAA) at this server’s public IP.

---

## 3. Application layout

Use a fixed path (example **`/opt/safro-callisto`**):

```bash
sudo mkdir -p /opt/safro-callisto
sudo chown deploy:deploy /opt/safro-callisto
```

As `deploy`:

```bash
cd /opt/safro-callisto
git clone <your-fork-or-repo-url> .
# or rsync/scp your checkout — same layout as this monorepo’s safro-callisto/ root
```

You need the **`safro-callisto`** directory contents at `/opt/safro-callisto` (i.e. `docker-compose.yml`, `deploy/`, `hasura/`, `.callisto/`, `Makefile`, etc.).

---

## 4. Secrets and `.env` (production)

1. **Never commit** production `.env`.

2. Create `/opt/safro-callisto/.env` with **strong** values:

   ```bash
   POSTGRES_USER=callisto
   POSTGRES_PASSWORD=<long-random>
   POSTGRES_DB=callisto
   HASURA_GRAPHQL_ADMIN_SECRET=<long-random-different-from-postgres>
   ```

3. Lock it down:

   ```bash
   chmod 600 /opt/safro-callisto/.env
   ```

4. **Align Callisto DB URL** in `.callisto/config.yaml` with the same user/password/db and **`localhost:5434`** (matches published port in compose).

The production Compose overlay reads `HASURA_GRAPHQL_ADMIN_SECRET` from this file (see `deploy/docker-compose.production.yml`).

---

## 5. Build Callisto on the server

Install **Go** (match your module’s `go` version) and build:

```bash
cd /opt/safro-callisto
make build
test -x build/callisto
```

Alternatively, build in CI and ship **`build/callisto`** + matching `.callisto/config.yaml` (same architecture, e.g. `linux/amd64`).

---

## 6. Start Postgres + Hasura (Docker, production bind)

From `/opt/safro-callisto`:

```bash
docker compose -f docker-compose.yml -f deploy/docker-compose.production.yml --env-file .env up -d
```

Verify:

```bash
docker ps
curl -sS http://127.0.0.1:8080/healthz
```

**First-time (or after metadata changes):** apply Hasura metadata (needs [Hasura CLI](https://hasura.io/docs/latest/hasura-cli/install-hasura-cli/)):

```bash
export HASURA_GRAPHQL_ADMIN_SECRET='(same as in .env)'
./scripts/hasura-metadata-apply.sh
```

Point `hasura/config.yaml` `endpoint` at `http://localhost:8080` (default in repo) when running on the server.

---

## 7. systemd units (services)

Examples live in **`deploy/systemd/`**. Install as root:

```bash
sudo cp /opt/safro-callisto/deploy/systemd/safro-indexer-docker.service.example /etc/systemd/system/safro-indexer-docker.service
sudo cp /opt/safro-callisto/deploy/systemd/callisto.service.example /etc/systemd/system/callisto.service
```

Edit both files and set:

- **`User=` / `Group=`** → your deploy user  
- **`WorkingDirectory=`** and paths → `/opt/safro-callisto` if you used that layout  

Enable and start **Docker stack first**, then Callisto:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now safro-indexer-docker.service
sleep 10   # let Postgres/Hasura become healthy
sudo systemctl enable --now callisto.service
sudo systemctl status safro-indexer-docker.service callisto.service
```

**Ordering:** `callisto.service` is `After=safro-indexer-docker.service`. If Callisto still starts before DB is ready, it will retry; you can add `ExecStartPre=/bin/sleep 15` temporarily or a small wait script.

**Logs:**

```bash
journalctl -u callisto.service -f
journalctl -u safro-indexer-docker.service -f
docker logs -f safro-hasura
```

---

## 8. Nginx + TLS for `sf-indexer-testnet.safrochain.com`

1. Copy the example site config:

   ```bash
   sudo cp /opt/safro-callisto/deploy/nginx-sf-indexer-testnet.conf.example \
     /etc/nginx/sites-available/sf-indexer-testnet.conf
   sudo ln -sf /etc/nginx/sites-available/sf-indexer-testnet.conf /etc/nginx/sites-enabled/
   sudo nginx -t && sudo systemctl reload nginx
   ```

2. **TLS** with [Certbot](https://certbot.eff.org/) (nginx plugin):

   ```bash
   sudo apt install -y certbot python3-certbot-nginx
   sudo certbot --nginx -d sf-indexer-testnet.safrochain.com
   ```

3. Uncomment/adjust **`listen 443 ssl`**** and certificate paths in the site file if you maintain the config manually; certbot often patches the active server block for you.

4. **Explorer / frontend** should use:

   - **GraphQL HTTP:** `https://sf-indexer-testnet.safrochain.com/v1/graphql`  
   - **GraphQL WS:** `wss://sf-indexer-testnet.safrochain.com/v1/graphql`  

   Update `chain.json` (or env) in Big Dipper accordingly.

**Hardening:**

- Keep **`HASURA_GRAPHQL_ENABLE_CONSOLE: "false"`** in production (set in `deploy/docker-compose.production.yml`).  
- Do not proxy `/v1/metadata` or `/v1/console` publicly unless IP-restricted or behind VPN.  
- Optional: `limit_req` in `http {}` for `/v1/graphql` (see comments in the nginx example).

---

## 9. Safe operational checklist

| Topic | Practice |
|--------|----------|
| Secrets | Only in `.env` (600) or secret manager; rotate if leaked |
| Updates | Pin image tags; test upgrades on staging; `docker compose pull` during maintenance |
| Backups | Schedule `pg_dump` from localhost:5434 (or volume snapshots) |
| Monitoring | Alert on `systemctl is-active`, Hasura `/healthz`, disk usage |
| Chain RPC | Archive vs pruned: see `docs/INDEXER-SYNC.md` and `parsing.start_height` |
| Admin secret | Hasura admin key is powerful — never expose in browser apps; use `anonymous` role for public GraphQL |

---

## 10. Deploy / upgrade flow (repeatable)

On the server as `deploy`:

```bash
cd /opt/safro-callisto
git pull   # or deploy artifact
make build   # if Go sources changed

sudo systemctl stop callisto.service
docker compose -f docker-compose.yml -f deploy/docker-compose.production.yml --env-file .env pull
docker compose -f docker-compose.yml -f deploy/docker-compose.production.yml --env-file .env up -d
# wait for healthy
./scripts/hasura-metadata-apply.sh   # when metadata changed only

sudo systemctl start callisto.service
```

---

## 11. Files added for this workflow

| File | Purpose |
|------|---------|
| `deploy/docker-compose.production.yml` | Localhost binds + production Hasura flags + `host-gateway` for actions |
| `deploy/nginx-sf-indexer-testnet.conf.example` | Reverse proxy for GraphQL (+ health, optional version) |
| `deploy/systemd/safro-indexer-docker.service.example` | systemd: bring up Docker stack on boot |
| `deploy/systemd/callisto.service.example` | systemd: Callisto indexer |

If your install path is not `/opt/safro-callisto`, replace it everywhere (systemd `WorkingDirectory`, `ExecStart`, docs).
