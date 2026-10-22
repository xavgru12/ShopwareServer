-- The order confirmation mail (order_confirmation_mail) is only sent after
-- payment (see flow-after-payment.sql), so its "you will receive a separate
-- notification once your payment has been made" sentence is misleading.
-- Replace it with a text that matches the post-payment point in time.
--
-- Idempotent (REPLACE on the exact old string): safe to run on every deploy.
-- Run against the Shopware database, e.g.:
--   mysql --default-character-set=utf8mb4 -u shopware -p shopware < mail-template-after-payment.sql

SET NAMES utf8mb4;

-- English (en-GB)
UPDATE mail_template_translation mtt
JOIN mail_template mt ON mt.id = mtt.mail_template_id
JOIN mail_template_type mty ON mty.id = mt.mail_template_type_id
SET mtt.content_html = REPLACE(content_html,
    'As soon as your payment has been made, you will receive a separate notification and your order will be processed.<br>',
    'We have received your payment and will now process your order.<br>')
WHERE mty.technical_name = 'order_confirmation_mail'
  AND mtt.language_id = UNHEX('2fbb5fe2e29a4d70aa5854ce7ce3e20b');

UPDATE mail_template_translation mtt
JOIN mail_template mt ON mt.id = mtt.mail_template_id
JOIN mail_template_type mty ON mty.id = mt.mail_template_type_id
SET mtt.content_plain = REPLACE(content_plain,
    'As soon as your payment has been made, you will receive a separate notification and your order will be processed.',
    'We have received your payment and will now process your order.')
WHERE mty.technical_name = 'order_confirmation_mail'
  AND mtt.language_id = UNHEX('2fbb5fe2e29a4d70aa5854ce7ce3e20b');

-- German (de-DE)
UPDATE mail_template_translation mtt
JOIN mail_template mt ON mt.id = mtt.mail_template_id
JOIN mail_template_type mty ON mty.id = mt.mail_template_type_id
SET mtt.content_html = REPLACE(content_html,
    'Sobald ein Zahlungseingang erfolgt ist, erhalten Sie eine separate Benachrichtigung und Ihre Bestellung wird verarbeitet.<br>',
    'Wir haben Ihre Zahlung erhalten und werden Ihre Bestellung nun verarbeiten.<br>')
WHERE mty.technical_name = 'order_confirmation_mail'
  AND mtt.language_id = UNHEX('d9712b5552674d669aeecd16a191373a');

UPDATE mail_template_translation mtt
JOIN mail_template mt ON mt.id = mtt.mail_template_id
JOIN mail_template_type mty ON mty.id = mt.mail_template_type_id
SET mtt.content_plain = REPLACE(content_plain,
    'Sobald ein Zahlungseingang erfolgt ist, erhalten Sie eine separate Benachrichtigung und Ihre Bestellung wird verarbeitet.',
    'Wir haben Ihre Zahlung erhalten und werden Ihre Bestellung nun verarbeiten.')
WHERE mty.technical_name = 'order_confirmation_mail'
  AND mtt.language_id = UNHEX('d9712b5552674d669aeecd16a191373a');
