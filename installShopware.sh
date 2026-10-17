echo composer install
composer install

echo install Shopware
bin/console system:install --basic-setup --create-database

echo bin/console plugin:install --activate SwagPayPal
bin/console plugin:install --activate SwagPayPal

echo bin/console plugin:install --activate YoxaMyPlugin
bin/console plugin:install --activate YoxaMyPlugin
