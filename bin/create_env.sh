#!/bin/bash
set -e

command -v az >/dev/null 2>&1 || { echo >&2 "❌ This script requires you to have the Azure CLI installed (\`brew install azure-cli\`) but it's not installed. Aborting."; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../docker-files/.env.shared"

if [ -f "$ENV_FILE" ]; then
  echo "❌ $ENV_FILE already exists. Refusing to overwrite it."
  exit 1
fi

echo "Fetching secrets from staging key-vault..."
echo "Writing secrets to $ENV_FILE..."

{
  echo "## Azure Credentials"
  echo "AAD_CLIENT_ID=$(az keyvault secret show --vault-name opal-stg --name AzureADClientId | jq -r .value)"
  echo "AAD_CLIENT_SECRET=$(az keyvault secret show --vault-name opal-stg --name AzureADClientSecret | jq -r .value)"
  echo "AAD_TENANT_ID=$(az keyvault secret show --vault-name opal-stg --name AzureADTenantId | jq -r .value)"
  echo ""
  echo "## Launch Darkly Credentials"
  echo "LAUNCH_DARKLY_ENABLED=false"
  echo "LAUNCH_DARKLY_SDK_KEY=$(az keyvault secret show --vault-name opal-stg --name launch-darkly-sdk-key | jq -r .value)"
  echo ""
  echo "## Opal application configuration"
  echo "REDIS_CONNECTION_STRING=redis://redis:6379/"
  echo ""
  echo "# legacy config"
  echo "DEFAULT_APP_MODE=opal"
  echo "IS_LEGACY_MODE=false"
  echo "OPAL_LEGACY_GATEWAY_PASSWORD=$(az keyvault secret show --vault-name opal-stg --name OpalLegacyGatewayPassword | jq -r .value)"
  echo "OPAL_LEGACY_GATEWAY_URL=https://host.docker.internal:4553/opal"
  echo "OPAL_LEGACY_GATEWAY_USERNAME=$(az keyvault secret show --vault-name opal-stg --name OpalLegacyGatewayUsername | jq -r .value)"
  echo ""
  echo "# test support config"
  echo "OPAL_LOGGING_TEST_SUPPORT_ENABLED=true"
  echo "TESTING_SUPPORT_ENDPOINTS_ENABLED=true"
  echo ""
  echo "# log level config"
  echo "ROOT_LOG_LEVEL=off"
  echo "OPAL_LOG_LEVEL=debug"
  echo ""
  echo "# feature flagging level config (only used when LD is disabled)"
  echo "RELEASE_1A_ENABLED=true"
  echo "RELEASE_1B_ENABLED=true"
  echo ""
  echo "## Opal Test User Credentials"
  echo "OPAL_TEST_USER_PASSWORD=$(az keyvault secret show --vault-name opal-stg --name OpalTestUserPassword | jq -r .value)"

} > "$ENV_FILE"

echo "✅ Done! Created $ENV_FILE with secrets from staging key-vault."
