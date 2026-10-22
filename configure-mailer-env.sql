-- Use the environment MAILER_DSN for outgoing mails instead of the store's
-- mailer settings: clearing core.mailerSettings.emailAgent makes Shopware
-- fall back to the MAILER_DSN from the environment
-- (MailerTransportLoader::fromString).
--
--   local docker -> docker-compose: MAILER_DSN=smtp://mailer:1025 (Mailpit)
--   server      -> shared .env: Gmail SMTP DSN
--
-- core.basicInformation.email stays configured as the sender address.
--
-- Only emailAgent is deleted: if SMTP is ever configured in the admin UI
-- again, the remaining rows (host/port/...) are still available.
--
-- Idempotent: safe to run on every deploy.
-- Run against the Shopware database, e.g.:
--   mysql --default-character-set=utf8mb4 -u shopware -p shopware < configure-mailer-env.sql

SET NAMES utf8mb4;

DELETE FROM system_config
WHERE configuration_key = 'core.mailerSettings.emailAgent'
  AND sales_channel_id IS NULL;

DELETE FROM system_config
WHERE configuration_key = 'core.basicInformation.email'
  AND sales_channel_id IS NULL;

INSERT INTO system_config (id, configuration_key, configuration_value, sales_channel_id, created_at, updated_at)
VALUES
    (UNHEX(REPLACE(UUID(), '-', '')), 'core.basicInformation.email', JSON_OBJECT('_value', 'yoxa.eu@gmail.com'), NULL, NOW(3), NOW(3));
