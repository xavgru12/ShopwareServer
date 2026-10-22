-- The CMS page shown by the "shipping costs" link (system config
-- core.basicInformation.shippingPaymentInfoPage) advertised PayPal
-- ("Versandkostenfrei! Zahlung mit Paypal."). PayPal is no longer a payment
-- method: resolve the page from the system config (the same entry the
-- storefront uses for the link) and write its text element without the PayPal
-- sentence, keeping the heading and the free-shipping note.
-- Idempotent: once written, the content no longer matches the WHERE clauses.
-- Run against the Shopware database, e.g.:
-- mysql --default-character-set=utf8mb4 -u shopware -p shopware < shipping-payment-cms.sql

SET NAMES utf8mb4;

-- German (de-DE)
UPDATE cms_slot_translation cst
JOIN cms_slot s ON s.id = cst.cms_slot_id AND s.version_id = cst.cms_slot_version_id
JOIN cms_block b ON b.id = s.cms_block_id AND b.version_id = s.cms_block_version_id
JOIN cms_section sec ON sec.id = b.cms_section_id AND sec.version_id = b.cms_section_version_id
JOIN system_config sc ON UNHEX(JSON_UNQUOTE(JSON_EXTRACT(sc.configuration_value, '$._value'))) = sec.cms_page_id
SET cst.config = JSON_SET(
    cst.config,
    '$.content.value',
    '<h2>Versand und Zahlung</h2><hr /><p>Versandkostenfrei!</p>'
)
WHERE sc.configuration_key = 'core.basicInformation.shippingPaymentInfoPage'
AND cst.language_id = UNHEX('d9712b5552674d669aeecd16a191373a')
AND JSON_EXTRACT(cst.config, '$.content.value') IS NOT NULL
AND JSON_UNQUOTE(JSON_EXTRACT(cst.config, '$.content.value')) <> '<h2>Versand und Zahlung</h2><hr /><p>Versandkostenfrei!</p>';

-- English (en-GB)
UPDATE cms_slot_translation cst
JOIN cms_slot s ON s.id = cst.cms_slot_id AND s.version_id = cst.cms_slot_version_id
JOIN cms_block b ON b.id = s.cms_block_id AND b.version_id = s.cms_block_version_id
JOIN cms_section sec ON sec.id = b.cms_section_id AND sec.version_id = b.cms_section_version_id
JOIN system_config sc ON UNHEX(JSON_UNQUOTE(JSON_EXTRACT(sc.configuration_value, '$._value'))) = sec.cms_page_id
SET cst.config = JSON_SET(
    cst.config,
    '$.content.value',
    '<h2>Payment / Shipping</h2><hr /><p>Shipping is free of charge.</p>'
)
WHERE sc.configuration_key = 'core.basicInformation.shippingPaymentInfoPage'
AND cst.language_id = UNHEX('2fbb5fe2e29a4d70aa5854ce7ce3e20b')
AND JSON_EXTRACT(cst.config, '$.content.value') IS NOT NULL
AND JSON_UNQUOTE(JSON_EXTRACT(cst.config, '$.content.value')) <> '<h2>Payment / Shipping</h2><hr /><p>Shipping is free of charge.</p>';
