#!/bin/bash
set -e

# Deploy with Deployer to the webhost (see deploy.php).
# Requires: the shared folder and database configured on the webhost
# (copy contents into the shared folder, run system:install there once).
# The `dep` binary runs with the host's PHP (only used to drive SSH).

cp ./backup/storefront.yaml ./config/packages/
echo "vendor/deployer/deployer/dep deploy -vvv"
vendor/deployer/deployer/dep deploy -vvv
rm ./config/packages/storefront.yaml
