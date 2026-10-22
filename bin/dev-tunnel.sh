#!/usr/bin/env bash
set -euo pipefail

COMPOSE=(docker compose)

log() { printf '\033[1;36mdev-tunnel:\033[0m %s\n' "$*"; }

# 1. make sure the local shop is running (database healthy first)
log 'bringing up the shop stack'
"${COMPOSE[@]}" up -d --wait >/dev/null

# 2. start the cloudflared quick tunnel (URL changes on every restart)
log 'starting cloudflared tunnel'
docker rm -f cloudflared >/dev/null 2>&1 || true
docker run -d --name cloudflared --network host \
    cloudflare/cloudflared:latest tunnel --no-autoupdate --url http://localhost:8000 \
    >/dev/null

# 3. wait until cloudflared prints the public URL
URL=""
for _ in $(seq 1 60); do
    URL="$(docker logs cloudflared 2>&1 | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | head -1 || true)"
    [ -n "$URL" ] && break
    sleep 2
done
if [ -z "$URL" ]; then
    log 'ERROR: no tunnel URL, check "docker logs cloudflared"' >&2
    exit 1
fi
HOST="${URL#https://}"
log "tunnel URL: ${URL}"

# 4. persist APP_URL + TUNNEL_HOST in .env.local (gitignored, used by web env_file)
touch .env.local
grep -vE '^(APP_URL|TUNNEL_HOST)=' .env.local > .env.local.tmp || true
printf 'APP_URL=%s\nTUNNEL_HOST=%s\n' "$URL" "$HOST" >> .env.local.tmp
mv .env.local.tmp .env.local

# 5. recreate web: new APP_URL + Caddy X-Forwarded-Proto fix for the tunnel host
log 'restarting web with tunnel config'
"${COMPOSE[@]}" up -d web >/dev/null

# 6. wait until the shop answers again
log 'waiting for the shop'
for _ in $(seq 1 30); do
    curl -fsS -o /dev/null http://127.0.0.1:8000/ 2>/dev/null && break
    sleep 2
done
if ! curl -fsS -o /dev/null http://127.0.0.1:8000/ 2>/dev/null; then
    log 'WARNING: shop not reachable on http://127.0.0.1:8000 yet' >&2
fi

# 7. register the tunnel URL as a sales channel domain (127.0.0.1 keeps working):
#    - re-point any previous trycloudflare domain to the new URL
#    - add the new URL to every sales channel that lacks it (headless excluded)
log 'registering sales channel domain'
"${COMPOSE[@]}" exec -T database sh -c 'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' 2>/dev/null <<SQL
UPDATE sales_channel_domain d
SET url = '${URL}'
WHERE d.url LIKE '%.trycloudflare.com'
  AND d.url <> '${URL}'
  AND d.sales_channel_id NOT IN (SELECT sales_channel_id FROM (SELECT sales_channel_id FROM sales_channel_domain WHERE url = '${URL}') tmp);

INSERT INTO sales_channel_domain (id, sales_channel_id, language_id, currency_id, snippet_set_id, url, created_at, updated_at)
SELECT UUID_TO_BIN(UUID()), d.sales_channel_id, d.language_id, d.currency_id, d.snippet_set_id, '${URL}', NOW(3), NOW(3)
FROM sales_channel_domain d
WHERE d.url NOT LIKE 'default.headless%'
  AND d.sales_channel_id NOT IN (SELECT sales_channel_id FROM (SELECT sales_channel_id FROM sales_channel_domain WHERE url = '${URL}') tmp2)
GROUP BY d.sales_channel_id;
SQL

# 8. rebuild the cache (APP_URL changed) and re-register the Stripe app (binds to the shop URL)
log 'clearing cache'
"${COMPOSE[@]}" exec web bin/console cache:clear >/dev/null
log 'installing/refreshing StripePaymentsApp'
if ! "${COMPOSE[@]}" exec web bin/console app:install --activate --force StripePaymentsApp; then
    log 'WARNING: app registration failed (see output above)' >&2
fi

cat <<EOF

Tunnel ready:
  Storefront: ${URL}
  Admin:      ${URL}/admin
EOF
