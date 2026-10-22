-- Change the flow builder so the order confirmation mail ("Bestellung") is
-- only sent after payment:
--
-- 1. Deactivate the "Order placed" flow (checkout.order.placed), which sends
--    the order confirmation mail immediately at checkout.
-- 2. Point the mail action of the "Payment enters status paid" flow
--    (state_enter.order_transaction.state.paid) at the order_confirmation_mail
--    template instead of the order_transaction.state.paid template.
--
-- Afterwards the serialized flow payloads must be regenerated:
--   bin/console dal:refresh:index --only=flow.indexer
--
-- Idempotent: safe to run on every deploy.
-- Run against the Shopware database, e.g.:
--   mysql --default-character-set=utf8mb4 -u shopware -p shopware < flow-after-payment.sql

SET NAMES utf8mb4;

-- 1. No order confirmation mail before payment.
UPDATE flow
SET active = 0,
    updated_at = NOW(3)
WHERE event_name = 'checkout.order.placed'
  AND active = 1;

-- 2. Order confirmation mail after payment.
UPDATE flow_sequence fs
JOIN flow f ON f.id = fs.flow_id
SET fs.config = JSON_SET(
    fs.config,
    '$.mailTemplateId',
    LOWER(HEX((
        SELECT mt.id
        FROM mail_template mt
        JOIN mail_template_type mty ON mty.id = mt.mail_template_type_id
        WHERE mty.technical_name = 'order_confirmation_mail'
          AND mt.system_default = 1
        LIMIT 1
    )))
)
WHERE f.event_name = 'state_enter.order_transaction.state.paid'
  AND fs.action_name = 'action.mail.send'
  AND fs.parent_id IS NULL
  AND fs.rule_id IS NULL
  AND JSON_UNQUOTE(JSON_EXTRACT(fs.config, '$.mailTemplateId'))
      <> LOWER(HEX((
          SELECT mt.id
          FROM mail_template mt
          JOIN mail_template_type mty ON mty.id = mt.mail_template_type_id
          WHERE mty.technical_name = 'order_confirmation_mail'
            AND mt.system_default = 1
          LIMIT 1
      )));
