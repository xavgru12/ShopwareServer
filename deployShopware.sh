#!/bin/bash
set -e

# Deploy with Deployer to the webhost (see deploy.php).
# Usage: ./deployShopware.sh [production|test]
#   production -> production-server host (yoxa.eu)
#   test       -> test-server host (test.yoxa.eu)
# Requires: the shared folder and database configured on the webhost
# (copy contents into the shared folder, run system:install there once).
# The `dep` binary runs with the host's PHP (only used to drive SSH).

case "${1:-}" in
    production) HOST_ALIAS="production-server" ;;
    test) HOST_ALIAS="test-server" ;;
    *)
        echo "Usage: $0 [production|test]" >&2
        exit 1
        ;;
esac

trap 'rm -f ./config/packages/storefront.yaml' EXIT
cp ./backup/storefront.yaml ./config/packages/
echo "vendor/deployer/deployer/dep deploy $HOST_ALIAS -vvv"
vendor/deployer/deployer/dep deploy "$HOST_ALIAS" -vvv
