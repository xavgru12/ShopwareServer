# Shopware Server

Shopware 6.4 project (Symfony Flex template). Setup follows the official guide:
https://developer.shopware.com/docs/v6.5/guides/installation/template.html

## Prerequisites

- PHP 8.1 with extensions
- Composer
- Docker + Docker Compose
- Symfony CLI

### PHP

```bash
sudo add-apt-repository ppa:ondrej/php
sudo apt-get install -y php8.1-fpm php8.1-mysql php8.1-curl php8.1-gd php8.1-xml php8.1-zip php8.1-opcache php8.1-mbstring php8.1-intl php8.1-cli
```

Choose the PHP version in case several are installed:

```bash
sudo update-alternatives --config php
```

### Composer

```bash
sudo apt install composer -y
```

### Symfony CLI

Required to run the app locally (see "Run" below). Install per https://symfony.com/download

## Install from scratch

### 1. Database

```bash
docker compose up -d database
```

Wait until MySQL is ready:

```bash
docker exec shopwareserver-database-1 mysqladmin ping -h127.0.0.1 -uroot -p'<db-password>' --silent
```

> **Important:** `MYSQL_VERSION=8.0` in `.env` is required. The `mysql:8` tag
> now resolves to MySQL 8.4, which rejects foreign keys referencing composite
> primary keys — Shopware 6.4 migrations rely on this everywhere and fail with
> `ERROR 6125 Failed to add the foreign key constraint. Missing unique key`.
> Shopware 6.4 only supports MySQL 8.0.

### 2. Install Shopware

Make sure `APP_URL` in `.env` is set to your dev URL — `system:install` creates
the storefront sales channel with exactly this URL as its domain. Then run:

Caution: Create database will drop the current database.
```bash
composer install
bin/console system:install --basic-setup --create-database
```

### 3. Activate plugins

```bash
bin/console plugin:install --activate SwagPayPal
bin/console plugin:install --activate YoxaMyPlugin
```

```bash
bin/console cache:clear
```

If the shop was already installed with a different/wrong `APP_URL`, the sales
channel domain in the DB is wrong and needs fixing — see
"Fix sales channel domain" below. On a fresh install with the correct
`APP_URL`, no DB commands are needed.

## Run

```bash
symfony serve -d --port=8000 --no-tls
```

Symfony CLI auto-detects the document root (`public/`) and the passthru
(`public/index.php`), so static assets and routed URLs both work.

- Storefront: http://localhost:8000
- Admin: http://localhost:8000/admin

Stop the server:

```bash
symfony server:stop
```

Logs:

```bash
symfony server:log
```

## Default credentials

- Admin user: `admin`
- Admin password: `shopware`

Change after first login.

## Fix sales channel domain (only if the shop was already set up)

Only needed when the shop was already installed with a different/wrong
`APP_URL`. The storefront only answers on domains registered in
`sales_channel_domain`; a wrong entry causes
`Unable to find a matching sales channel`.

Update the existing domain to the local dev URL:

```bash
docker exec shopwareserver-database-1 mysql -u shopware -p'<db-password>' shopware -e "UPDATE sales_channel_domain SET url='http://127.0.0.1:8000' WHERE url='http://127.0.0.1/ShopwareServer/public';"
```

Optionally add `localhost:8000` as a second domain:

```bash
docker exec shopwareserver-database-1 mysql -u shopware -p'<db-password>' shopware -e "INSERT INTO sales_channel_domain (id, url, sales_channel_id, language_id, currency_id, snippet_set_id, created_at, updated_at) SELECT UNHEX(REPLACE(UUID(),'-','')), 'http://localhost:8000', sales_channel_id, language_id, currency_id, snippet_set_id, NOW(3), NOW(3) FROM sales_channel_domain WHERE url='http://127.0.0.1:8000' LIMIT 1;"
```

```bash
bin/console cache:clear
```

## Configuration

Key settings in `.env`:

| Variable | Value | Purpose |
|---|---|---|
| `APP_URL` | `http://127.0.0.1:8000` | Public app URL |
| `DATABASE_URL` | `mysql://shopware:!ChangeMe!@127.0.0.1:3306/shopware` | DB connection, matches the `database` service in `docker-compose.yml` |
| `MYSQL_VERSION` | `8.0` | Pin MySQL to 8.0 (see note above) |
| `SHOPWARE_ES_ENABLED` | `0` | Elasticsearch/OpenSearch disabled (OpenSearch container not required) |

`docker-compose.override.yml` pins the database to host port `3306` so the
`.env` connection string stays stable (otherwise Compose assigns a random
host port).

> Note: Shopware recommends putting overrides in `.env.local` because `.env`
> is overwritten by the web updater. Currently the overrides live in `.env`.

## Placeholders to change

The following values are placeholders or machine-specific secrets and **must
be replaced** for any real deployment:

| Placeholder | Where | Example replacement |
|---|---|---|
| `!ChangeMe!` (DB passwords) | `docker-compose.yml` defaults and `DATABASE_URL` in `.env` (URL-encoded as `%21ChangeMe%21`) | `<db-password>` |
| `MAILER_DSN` (contains real Gmail credentials) | `.env` | `<mailer-dsn>` (e.g. `null://null` for local dev, `smtp://<user>:<password>@<host>:<port>` for production) |
| `APP_URL` | `.env` and `sales_channel_domain.url` in the DB | `<your-domain>` (e.g. `https://shop.example.com`) |

`APP_SECRET` (Symfony secret for CSRF/session signing) and `INSTANCE_ID`
(unique shop identifier) are generated by Shopware itself — normally by
`bin/console system:setup`, which writes them into `.env`. The values shipped
in the Symfony Flex template are just pre-generated defaults; both should be
random and unique per installation.

Example `.env` with placeholders:

```dotenv
APP_URL=https://<your-domain>
APP_SECRET=<app-secret>
INSTANCE_ID=<instance-id>
DATABASE_URL="mysql://shopware:<db-password>@127.0.0.1:3306/shopware"
MAILER_DSN=smtp://<user>:<password>@<host>:<port>
MYSQL_VERSION=8.0
```

If you change the DB password, set it in both `docker-compose.yml`
(`MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD`) and `DATABASE_URL`, then recreate
the DB container (`docker compose up -d --force-recreate database`).

## Troubleshooting

### `ERROR 6125 Failed to add the foreign key constraint. Missing unique key`

The MySQL image is 8.4 (see the note above). Check with
`docker exec shopwareserver-database-1 mysql -uroot -p'<db-password>' -e "SELECT VERSION();"`.
Fix: set `MYSQL_VERSION=8.0` in `.env`, then recreate the container and volume:

```bash
docker compose stop database && docker compose rm -f database
docker volume rm shopwareserver_db-data
docker compose up -d database
```

### `Cannot create private key config/jwt/private.pem, it already exists`

Stale JWT keys from a previous install attempt. Delete them and re-run
`bin/console system:install`:

```bash
rm config/jwt/private.pem config/jwt/public.pem
```

### Blank admin page

The assets (`/bundles/...`) aren't being served. Run via `symfony serve`.

### `Unable to find a matching sales channel for the request`

The requested host isn't registered in `sales_channel_domain`. See
"Fix sales channel domain" above.

### `Unable to connect to database` / wrong port

The DB container must be running (`docker compose up -d database`) and
`DATABASE_URL` must use port `3306` (see Configuration).
