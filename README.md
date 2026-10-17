# Shopware Server

Shopware 6.7 project (Symfony Flex template) with the official Docker dev
environment (`ghcr.io/shopware/docker-dev` image, per the Shopware 6.7 Docker
setup).

## Prerequisites

- Docker + Docker Compose
- `make` (optional — wraps the docker compose commands)

PHP, Composer, MySQL and Caddy all run inside Docker; nothing else needs to be
installed on the host.

## URLs

| Service | URL |
|---|---|
| Storefront | http://127.0.0.1:8000 |
| Admin | http://127.0.0.1:8000/admin |
| Adminer (DB UI) | http://127.0.0.1:9080 |
| Mailpit (mail UI) | http://127.0.0.1:8025 |

Default admin credentials: `admin` / `shopware` (change after first login).

## Daily development

```bash
make up                        # docker compose up -d
make shell                     # bash inside the web container
make down                      # stop containers
docker compose logs -f web     # logs
```

All console commands run inside the `web` container:

```bash
docker compose exec web bin/console cache:clear
docker compose exec web bin/console plugin:list
docker compose exec web bin/console dal:refresh:index
```

### Plugins

Plugins live as git submodules under `custom/plugins/` (e.g. `YoxaMyPlugin`),
loaded via the composer path repositories. Install/activate with:

```bash
docker compose exec web bin/console plugin:install --activate YoxaMyPlugin
```

Git operations for plugins happen inside the submodule repos; the container
only runs the code.

### Frontend development

Only rebuild assets after JS/SCSS changes:

```bash
make build-storefront            # bin/build-storefront.sh in container
make watch-storefront            # hot reload proxy (uses port 9998)
make build-administration
```

## Install from scratch

1. `docker compose up -d` (wait until the database is healthy)
2. `docker compose exec web composer install`
3. `docker compose exec web bin/console system:install --basic-setup --create-database`

   > **Caution:** `--create-database` drops the current database.
4. Activate plugins and clear the cache:

   ```bash
   docker compose exec web bin/console plugin:install --activate YoxaMyPlugin
   docker compose exec web bin/console cache:clear
   ```

`installShopware.sh` runs the same steps; the `make setup` target adds
`--drop-database --force` and is only for fresh setups.

## Updating Shopware (official flow)

1. Bump the version constraint in `composer.json` (currently
   `"shopware/core": "6.7.*"`).
2. In the container:

   ```bash
   docker compose exec web composer update --no-interaction
   ```

3. Sync the project files (`.env`, `bin/`, `config/`, `public/index.php`,
   `docker-compose.yml`, …) to the new version via the official recipe reset —
   this is what the `shopware-cli project upgrade` wizard runs internally:

   ```bash
   docker compose exec web composer symfony:recipes:install --force --reset
   ```

   > `composer recipes:update` (the interactive variant) requires a clean
   > git index; use the `--force --reset` variant when changes are
   > uncommitted.
4. Restore project-specific values that the recipe reset overwrites with
   template defaults — **`.env`** (DB credentials, `MAILER_DSN`,
   `APP_ENV=debug`, `MYSQL_VERSION=8.0`) and the `database` service in
   `docker-compose.yml` (**MySQL 8.0**, not the template's mariadb default —
   the existing data volume is MySQL).
5. Run migrations and finish:

   ```bash
   docker compose exec web bin/console system:update:finish
   ```

6. Verify: `bin/console --version`, `plugin:list`, open the storefront/admin.

## Demo data

The shop runs the official Demostore demo data (faker-generated):

```bash
docker compose exec web bin/console framework:demodata -e prod --reset-defaults \
  --products 60 --customers 3 --categories 3 --media 60 --orders 2 \
  --manufacturers 5 --tags 10 --reviews 10 --promotions 2 --properties 2 \
  --mail-template 0 --mail-header-footer 0 --users 0
docker compose exec web bin/console dal:refresh:index
```

- Requires `shopware/dev-tools` (dev dependency).
- Must run with `-e prod` (the command refuses other environments).
- **Known core bug:** `--tags` must be `>= 10` — the media generator picks a
  random 0–9 tags and crashes with `Cannot get N elements, only M in array`
  if fewer exist.
- `--mail-template 0` keeps the YoxaMyPlugin mail template changes intact.
- `--reset-defaults` only zeroes the generator counts — it does **not**
  delete existing data. Old (e.g. 6.4-era) demo categories survive a
  regeneration; delete them first for a clean tree.
- After regenerating, clear the cache pools and restart `web`, otherwise the
  header navigation can keep serving an empty tree (see Troubleshooting).
- The demo category layouts ship with a sidebar section (category
  navigation + filter next to the top navbar). That sidebar was removed
  from both demo layouts (via SQL on `cms_slot`/`cms_block`/`cms_section`)
  so category pages render single-column. Re-running demodata restores it.

## Configuration

Key settings in `.env`:

| Variable | Value | Purpose |
|---|---|---|
| `APP_ENV` | `debug` | Dev environment (template default is `prod`) |
| `APP_URL` | `http://127.0.0.1:8000` | Public app URL |
| `DATABASE_URL` | `mysql://shopware:!ChangeMe!@database:3306/shopware` | Host `database` = compose service name |
| `MYSQL_VERSION` | `8.0` | Pin MySQL to 8.0 — MySQL 8.4 rejects the composite FK keys Shopware uses |
| `SHOPWARE_ES_ENABLED` | `0` | Elasticsearch/OpenSearch disabled |

`docker-compose.override.yml` exposes the database on host port `3306`.
Real credentials belong in `.env.local` (gitignored); `.env` only carries
placeholders/dev values.

### docker-compose specifics (deviations from the template)

- `web`: official `ghcr.io/shopware/docker-dev:php8.3-node24-caddy` image,
  project mounted at `/var/www/html`, runs as uid 1000 (matches the host
  user — no permission issues).
- Ports are bound to `127.0.0.1` (IPv4 loopback only). On this machine
  `localhost` resolves to `::1` first, and Shopware rejects requests whose
  `Host` header is `[::1]:8000` with a "Domain Mapping Misconfiguration"
  400 — binding IPv4-only makes browsers fall back to `127.0.0.1`.
- `dns: 1.1.1.1, 8.8.8.8` — this host's systemd-resolved stub
  (`127.0.0.53`) is unreachable from containers.
- Host port `8080` was busy (unrelated VM), so the template's
  `8080:8080` mapping was dropped; only `8000`/`9999`/`9998`/`5173`/`5773`
  are published.
- `database` stays `mysql:8.0-oracle` with the existing `db-data` volume
  (template default is mariadb 11.8 — do not switch on an existing volume).

## Deployment

Deployer to all-inkl shared hosting (`deploy.php`, run via
`./deployShopware.sh`):

- Webhost requirements: PHP >= 8.2, MySQL >= 8.0.22 or MariaDB >= 10.11.6.
- After deploy on the server:

  ```bash
  bin/console system:update:prepare
  bin/console system:update:finish
  ```

## Troubleshooting

### MySQL 8.4 breaks migrations (`ERROR 6125`)

`mysql:8` resolves to MySQL 8.4, which rejects foreign keys referencing
composite primary keys — Shopware relies on these. Keep `MYSQL_VERSION=8.0`
in `.env` (Shopware 6.7 supports MySQL >= 8.0.22).

### Port 8000 already in use

Stop the old Symfony dev server (`symfony server:stop`) or change the host
port mapping of the `web` service in `docker-compose.yml`.

### `Unable to find a matching sales channel`

The requested host isn't registered in `sales_channel_domain`. Check
`bin/console sales-channel:list` and update the domain if `APP_URL` changed.

### Old demo layouts look broken after an upgrade

Pre-6.7 CMS layouts (e.g. category pages with sidebar navigation) render
confusingly in the new theme. Regenerate demo data (see above).

### Navigation/navbar empty or stale after data changes

The category tree for the header navigation is cached in the filesystem
cache pool (`cache.object`, tag `category_level_loader`). Under some
conditions (e.g. mass deletes, or demodata running with `-e prod` while
HTTP runs in the `debug` env) stale entries survive `cache:clear` and
`cache:pool:clear` — the navbar then renders only "Home".

Fix: delete the pool directories and restart the web container:

```bash
docker compose exec web sh -c 'rm -rf var/cache/*/pools/*'
docker compose restart web
```

### `localhost` shows "Shopware Domain Mapping Misconfiguration" (400)

The browser sends `Host: [::1]:8000` over IPv6, which isn't a registered
sales channel domain. The `web` ports are bound to `127.0.0.1` only, so use
`http://127.0.0.1:8000` (or make sure the browser falls back to IPv4).
