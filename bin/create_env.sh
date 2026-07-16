#!/bin/bash
set -e

command -v az >/dev/null 2>&1 || { echo >&2 "❌ This script requires you to have the Azure CLI installed (\`brew install azure-cli\`) but it's not installed. Aborting."; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../docker-files/.env.shared"
CLEAN=false

usage() {
  cat <<'USAGE'
Usage: create_env.sh [-clean|-c] [-h|--help]

-clean, -c   Delete existing .env.shared (if present) and regenerate it
-h, --help   Show this help message
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -clean|-c)
      CLEAN=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ -f "$ENV_FILE" ]; then
  if [[ "$CLEAN" == "true" ]]; then
    echo "🧹 Removing existing $ENV_FILE"
    rm -f "$ENV_FILE"
  else
    read -r -p "⚠️  $ENV_FILE already exists. Replace it? [y/N]: " REPLY
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
      rm -f "$ENV_FILE"
    else
      echo "Skipping. Existing file was not changed."
      exit 0
    fi
  fi
fi

echo "Fetching secrets from staging key-vault..."
echo "Writing secrets to $ENV_FILE..."

aad_client_id="$(az keyvault secret show --vault-name opal-stg --name AzureADClientId | jq -r .value)"
aad_client_secret="$(az keyvault secret show --vault-name opal-stg --name AzureADClientSecret | jq -r .value)"
aad_tenant_id="$(az keyvault secret show --vault-name opal-stg --name AzureADTenantId | jq -r .value)"

{
  echo "## Azure Credentials"
  echo "AAD_CLIENT_ID=$aad_client_id"
  echo "AZURE_AD_CLIENT_ID=$aad_client_id"
  echo "AAD_CLIENT_SECRET=$aad_client_secret"
  echo "AZURE_AD_CLIENT_SECRET=$aad_client_secret"
  echo "AAD_TENANT_ID=$aad_tenant_id"
  echo "AZURE_AD_TENANT_ID=$aad_tenant_id"
  echo ""
  echo "## Launch Darkly Credentials"
  echo "LAUNCH_DARKLY_ENABLED=false"
  echo "LAUNCH_DARKLY_SDK_KEY=$(az keyvault secret show --vault-name opal-stg --name launch-darkly-sdk-key-test | jq -r .value)"
  echo ""
  echo "## Opal application configuration"
  echo "REDIS_CONNECTION_STRING=redis://host.docker.internal:6379"
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
  echo "RELEASE_1C_ENABLED=true"
  echo "RELEASE_1C_ENFORCEMENT_OPERATIONAL_REPORTING_ENABLED=true"
  echo "RELEASE_1C_WRITE_OFF_ENABLED=true"
  echo "RELEASE_1C_AUTO_ENFORCEMENT_ENABLED=true"
  echo "RELEASE_1D_DATA_RETENTION_ENABLED=true"
  echo "RELEASE_1D_AUTO_ENFORCEMENT_CONFIG_ENABLED=true"
  echo "RELEASE_1C_RM_FINANCIAL_MOVEMENTS_ENABLED=true"
  echo "RELEASE_1C_RM_FINANCIAL_CHECKS_ENABLED=true"
  echo "RELEASE_1C_RM_SUSPENSE_ENABLED=true"
  echo "RELEASE_1C_RM_PAYMENT_ENABLED=true"
  echo "RELEASE_1C_RM_ADMIN_REPORTS_ENABLED=true"
  echo "RELEASE_1C_RM_ACCOUNT_ACTIONS_ENABLED=true"
  echo "RELEASE_1C_FINANCIAL_MOVEMENTS_ENABLED=true"
  echo "RELEASE_1C_CHECKS_ENABLED=true"
  echo "RELEASE_1C_SUSPENSE_ENABLED=true"
  echo "RELEASE_1C_PAYMENT_ENABLED=true"
  echo "RELEASE_1C_R1A_TIDY_UP_ENABLED=true"
  echo "RELEASE_1C_REFERENCE_DATA_ENABLED=true"
  echo "RELEASE_1C_BANKING_INTERFACES_ENABLED=true"
  echo "RELEASE_1C_CPP_ENFORCEMENT_ENABLED=true"
  echo "RELEASE_1C_CPP_ENABLED=true"
  echo "RELEASE_1C_PRINTING_ENABLED=true"
  echo "OPAL_COMMON_CONTENT_DIGEST_REQUEST_AUTO_GENERATE=true"
  echo ""
  echo "## Opal Test User Credentials"
  echo "OPAL_TEST_USER_PASSWORD=$(az keyvault secret show --vault-name opal-stg --name OpalTestUserPassword | jq -r .value)"

} > "$ENV_FILE"

echo "✅ Done! Created $ENV_FILE with secrets from staging key-vault."
