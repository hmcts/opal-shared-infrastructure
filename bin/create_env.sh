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
  echo "AAD_CLIENT_ID=$(az keyvault secret show --vault-name opal-stg --name AzureADClientId | jq -r .value)"
  echo "AAD_CLIENT_SECRET=$(az keyvault secret show --vault-name opal-stg --name AzureADClientSecret | jq -r .value)"
  echo "AAD_TENANT_ID=$(az keyvault secret show --vault-name opal-stg --name AzureADTenantId | jq -r .value)"
  echo "OPAL_TEST_USER_PASSWORD=$(az keyvault secret show --vault-name opal-stg --name OpalTestUserPassword | jq -r .value)"
  echo "LAUNCH_DARKLY_SDK_KEY=$(az keyvault secret show --vault-name opal-stg --name launch-darkly-sdk-key | jq -r .value)"
  echo "LAUNCH_DARKLY_SDK_KEY=$(az keyvault secret show --vault-name opal-stg --name launch-darkly-sdk-key | jq -r .value)"
  echo "DEFAULT_APP_MODE=opal"
  echo "OPAL_LOGGING_TEST_SUPPORT_ENABLED=true"
  echo "TESTING_SUPPORT_ENDPOINTS_ENABLED=true"
} > "$ENV_FILE"

echo "✅ Done! Created $ENV_FILE with secrets from staging key-vault."
