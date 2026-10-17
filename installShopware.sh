#!/bin/bash
set -e

echo "starting containers"
docker compose up -d

echo "waiting for database"
until docker compose exec -T database mysqladmin ping -h localhost -u root -p"${MYSQL_ROOT_PASSWORD:-!ChangeMe!}" --silent 2>/dev/null; do
    sleep 2
done

echo "composer install"
docker compose exec web composer install

echo "install Shopware (drops the existing database!)"
docker compose exec web bin/console system:install --basic-setup --create-database

echo "activate plugins"
docker compose exec web bin/console plugin:install --activate YoxaMyPlugin

echo "compile theme and clear cache"
docker compose exec web bin/console theme:compile
docker compose exec web bin/console cache:clear
