# Shopware Server

Shopware 6.7 project with the official Docker dev environment
(`ghcr.io/shopware/docker-dev` image, per the Shopware 6.7 Docker setup).

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

`make up` (see the `up` target in `Makefile`) touches `.env.local` and runs
`docker compose up -d`. Compose starts `database` (MySQL 8), `opensearch` and
the `web` service (`docker-compose.yml`):

- `web` uses the official `ghcr.io/shopware/docker-dev:php8.3-node24-caddy`
  image with the project mounted at `/var/www/html`; it only starts after the
  database healthcheck passes.
- The container maps port `8000` to `127.0.0.1:8000` on the host — Caddy
  inside the container serves the shop on that port, so the storefront is
  available at http://127.0.0.1:8000.

```bash
make up                        # docker compose up -d
make shell                     # bash inside the web container
make down                      # stop containers
make dev-tunnel                # public HTTPS tunnel (Stripe/Shirtigo backends)
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

## Stripe payments — step-by-step setup

Official **Stripe Payments for Shopware 6 App** (`StripePaymentsApp`, free, by
Stripe). Requires Shopware >= 6.5.

### 1. Stripe account + test keys

1. Create an account at https://dashboard.stripe.com/register (or log in).
2. In the Dashboard top right, make sure **Test mode** is toggled on.
3. Developers → API keys → copy the **Publishable key** (`pk_test_…`) and
   **Secret key** (`sk_test_…`).

### 2. Shopware Account (Shopware Store) login

Required once per shop; the Store login needs a domain registered under
account.shopware.com → Shops (`localhost`/`127.0.0.1` are rejected — use your
real domain, e.g. `yoxa.eu`):

```bash
docker compose exec web bin/console store:login \
  --shopwareId=<shopware-account-email> --user=admin --host=yoxa.eu
```

- `--user` is the local admin username (`admin`)
- the password prompt expects the **Shopware Account** password (not the shop
  password)

### 3. Download and install the app

```bash
docker compose exec web bin/console store:download -p StripePaymentsApp
docker compose exec web bin/console app:install --activate --force StripePaymentsApp
```

`--force` auto-grants the permission list the app requests. Verify with
`bin/console app:list` — StripePaymentsApp active.

> The app registers against the shop's public URL. For a local shop this
> requires the HTTPS tunnel first (see below), otherwise registration gets a
> 403 from Stripe's backend.

### 4. Make the shop reachable (local dev tunnel)

The Stripe/Shirtigo backends only talk to publicly reachable HTTPS shops. One
command sets everything up and prints the domain:

```bash
make dev-tunnel
```

It does all of the following automatically:

1. Brings the stack up and starts a `cloudflared` quick tunnel
   (`cloudflare/cloudflared`, `--url http://localhost:8000`)
2. Waits for the tunnel URL and writes it to `.env.local`
   (`APP_URL` + `TUNNEL_HOST` — gitignored, not `.env` which is tracked)
3. Recreates `web` and registers the URL as a sales channel domain via SQL
   (an old tunnel domain from a previous run is re-pointed to the new URL;
   `127.0.0.1`/`localhost` domains stay intact, headless ones are skipped)
4. Clears the cache and re-runs `app:install --activate --force
   StripePaymentsApp` (registration binds to the shop URL; no-op if already
   installed)

`make dev-tunnel-down` removes the tunnel container.

**Caddy scheme fix (automated):** cloudflared terminates TLS and forwards the
request to the shop as plain `http://`, so Shopware would see scheme `http`
and reject the request with a 400 "Domain Mapping Misconfiguration" (the
registered sales channel domain is `https://…`). The `web` service in
`docker-compose.override.yml` injects the original scheme for the tunnel host:

```yaml
services:
  web:
    environment:
      CADDY_EXTRA_CONFIG: |
        @tunnelHost host {$TUNNEL_HOST:localhost.invalid}
      CADDY_SERVER_EXTRA_DIRECTIVES: request_header @tunnelHost X-Forwarded-Proto https
```

`{$TUNNEL_HOST:localhost.invalid}` is resolved by Caddy from the container
env (`TUNNEL_HOST` comes from `.env.local`); the `localhost.invalid` fallback
never matches, so without a tunnel http://127.0.0.1:8000 keeps working with
scheme `http`. (`request_header` needs a named matcher — inline matchers
don't parse there.)

Caveat: the quick-tunnel URL changes on every tunnel restart — re-run
`make dev-tunnel` after a restart. Production (`yoxa.eu`) needs no tunnel.

### 5. Connect the Stripe account

The current connector version (>= 1.5) does not take manual API keys — you
connect your Stripe account via OAuth:

1. Admin → **Extensions → My extensions → Apps** tab → **Stripe** → ⋯
   (overflow menu) → **Open extension**
   (this opens the Stripe Configuration page hosted by Stripe's backend)
2. Click **Connect with Stripe in Test Mode** (or **Live Mode** for
   production) and sign in to the Stripe account — no keys are pasted in
   Shopware
3. In the Stripe Dashboard, enable the payment methods for your Shopware
   account: **Settings → Payment methods → select your Shopware account** in
   the platform dropdown → turn on the methods you want

The connection can be set per sales channel: **Sales Channels** tab on the
Stripe Configuration page → uncheck **Use default account** → connect the
channel to its own Stripe account.

### 6. Checkout setup

The app auto-creates its payment method **"Pay online"** and assigns it to the
sales channels on registration. Verify in Admin → Settings → Payment:

- "Pay online" is active and assigned to the sales channel
- Deactivate/delete other payment methods if Stripe should be the only one
  (see note below: deleting needs the sales channel defaults updated)

### 7. Test purchase

1. Open the shop via the **tunnel URL** (not localhost)
2. Add a product → checkout → register as guest → confirm
3. The Stripe card form appears on the confirm page — use the test cards
4. On success the order goes to `/checkout/finish`; in the DB the transaction
   state is `paid` with `custom_fields.stripe_payment_context` containing
   `charge_id`/`payment_intent_id`

### Go-live checklist

- Dashboard: switch to **live mode**, verify the domain for Apple Pay
  (Settings → Payment methods → Apple Pay → Add domain)
- App config: **Connect with Stripe in Live Mode** and enable the live
  payment methods in the Dashboard
- Webhook: the app registers its webhooks itself via the shop URL — make sure
  the production shop is reachable on `https://<domain>`
- Re-run `app:install` on the production shop (registration binds to the
  production URL)

### Stripe test cards

With Stripe **test mode** keys configured:

| Card | Purpose |
|---|---|
| `4242 4242 4242 4242` (any future expiry, any CVC) | Successful payment, no 3-D Secure |
| `4000 0027 6000 3184` | Forces a 3-D Secure test flow ("Complete authentication") |
| `4000 0000 0000 0002` | Declined card |
| `4000 0000 0000 9995` | Insufficient funds |

A successful sandbox order records `charge_id`, `payment_intent_id` and
`payment_method_id` in the order transaction's
`custom_fields.stripe_payment_context`.

Note on Apple Pay: it only appears after the domain is registered/verified in
the Stripe dashboard **and** the customer is on an Apple device (Safari +
Wallet). The `…trycloudflare.com` tunnel domain can't be verified, so Apple
Pay never shows in local tests — expected, not a bug.

### Deleting other payment methods (Stripe only)

1. Deactivate first (`payment_method.active = 0`) — safer than deleting
2. If you delete via DAL: also update `sales_channel.payment_method_id`,
   `sales_channel.payment_method_ids`, and any `sales_channel_api_context`
   payloads still referencing the old ids, otherwise the cached sales channel
   context throws "Could not find payment method with id …"
3. Orders referencing a method block deletion (FK) — delete those orders
   first (demo data) or leave the method deactivated

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

### Test (test.yoxa.eu) — automatic

Every push to **any branch** triggers `.github/workflows/ShopwareDeployer.yml`:

- **`main`** → `dep deploy production` → `/www/htdocs/w01a5092/ShopwareServer`
  (yoxa.eu)
- **any other branch** → `dep deploy test` → `/www/htdocs/w01a5092/TestShop`
  (test.yoxa.eu)

Both targets live in `deploy.php` as `host('production')` and `host('test')`
— same task chain, only `deploy_path` differs. The workflow runs PHP 8.3 +
composer install on the runner, then `deployphp/action` uploads the
checked-out branch.

Requirements:

- GitHub secret `WEBHOST_SSH_SHOPWARE_PRIVATE_KEY` = PEM-format SSH private
  key of the deploy user (real newlines, no passphrase)
- GitHub secret `PRIVATE_REPO_KEY` = GitHub SSH deploy key for the private
  submodules (`shopware-stripe`, `ShopwareYoxaPlugin`) — used by the
  `webfactory/ssh-agent` step before checkout
- Shared `.env` on the server: `APP_URL=https://test.yoxa.eu` + test
  `DATABASE_URL`
- First deploy needs the shared folder/database set up on the webhost
  (copy the shared files and run `system:install` there once)

The Stripe app ships as a git submodule (`custom/apps/StripePaymentsApp`) and
is installed automatically on every deploy by the `sw:app:install` task
(`app:install` on first run, `app:refresh` afterwards). It also sets
`core.store.licenseHost` (`set('license_host', 'yoxa.eu')` in `deploy.php`)
which the store app-signature API requires. Enter the Stripe API keys once
per shop in Admin → Extensions → Stripe.

### Pre-compilation of frontend assets (currently disabled)

The webhost has no Node.js, so frontend source changes must be compiled
**before** the deploy (`sw-build-without-db` in `deploy.php`):

- **Theme CSS** (variables, colors, layout styles) is compiled server-side by
  `sw:theme:compile` (PHP, part of `sw:deploy`) — always happens, no Node
  needed.
- **Source SCSS/JS** (custom theme styles, storefront/admin JS plugins) needs
  the Node build: `bin/build-js.sh` runs locally/CI and the built assets are
  uploaded. `sw-build-without-db:get-remote-config` first downloads
  `plugins.json` + theme-config from the server's current release so the build
  works without DB access (skipped on the very first deploy — no release yet).

Why it's disabled: we run vanilla Shopware 6.7 without custom SCSS/JS, the
admin/storefront JS ships prebuilt in the packages, and neither the local
machine nor the CI runner has Node. Re-enable when frontend sources change:

1. `deploy.php`: uncomment `before('deploy:update_code', 'sw-build-without-db');`
2. Workflow: add `actions/setup-node@v4` (Node 22) before the deploy step
3. Note: the first build on a fresh server skips the remote-config download
   (no current release) — deploy once, then builds work from the second run on

### Production (all-inkl)

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

Free port 8000 (e.g. stop the process using it) or change the host port
mapping of the `web` service in `docker-compose.yml`.

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
