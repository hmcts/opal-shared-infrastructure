#!/usr/bin/env bash
set -euo pipefail

cleanup_keys() {
  if [[ -n "${PRIVATE_KEY_PATH:-}" && -f "${PRIVATE_KEY_PATH}" ]]; then
    rm -f "${PRIVATE_KEY_PATH}"
  fi

  if [[ -n "${PUBLIC_KEY_PATH:-}" && -f "${PUBLIC_KEY_PATH}" ]]; then
    rm -f "${PUBLIC_KEY_PATH}"
  fi
}

usage() {
  cat <<'EOF'
Generate an SSH key pair and create/update Azure Key Vault secrets.

Usage:
  bais-sftp-key.sh --keyvault-name <name> [options]

Required:
  --keyvault-name <name>          Azure Key Vault name

Optional:
  --subscription <id-or-name>     Azure subscription for az account set
  --output-dir <dir>              Directory to write keys (default: ./ssh)
  --key-name <name>               Key file basename (default: bais-sftp)
  --public-secret-name <name>     KV secret name for public key (default: bais-emulator-public-key)
  --private-secret-name <name>    KV secret name for private key (default: bais-emulator-private-key)
  --passphrase <value>            Key passphrase (default: empty)
  --force                         Overwrite existing local key files
  --help                          Show this help

Examples:
  ./ssh/bais-sftp-key.sh --keyvault-name opal-kv-demo

  ./ssh/bais-sftp-key.sh \
    --keyvault-name opal-kv-demo \
    --subscription 00000000-0000-0000-0000-000000000000 \
    --output-dir ./ssh/keys \
    --key-name bais-sftp-demo \
    --public-secret-name bais-emulator-public-key \
    --private-secret-name bais-emulator-private-key
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' was not found." >&2
    exit 1
  fi
}

KEYVAULT_NAME=""
SUBSCRIPTION=""
OUTPUT_DIR="./ssh"
KEY_NAME="bais-sftp"
PUBLIC_SECRET_NAME="bais-emulator-public-key"
PRIVATE_SECRET_NAME="bais-emulator-private-key"
PASSPHRASE=""
FORCE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keyvault-name)
      KEYVAULT_NAME="${2:-}"
      shift 2
      ;;
    --subscription)
      SUBSCRIPTION="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --key-name)
      KEY_NAME="${2:-}"
      shift 2
      ;;
    --public-secret-name)
      PUBLIC_SECRET_NAME="${2:-}"
      shift 2
      ;;
    --private-secret-name)
      PRIVATE_SECRET_NAME="${2:-}"
      shift 2
      ;;
    --passphrase)
      PASSPHRASE="${2:-}"
      shift 2
      ;;
    --force)
      FORCE="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$KEYVAULT_NAME" ]]; then
  echo "Error: --keyvault-name is required." >&2
  usage
  exit 1
fi

require_cmd az
require_cmd ssh-keygen

if ! az account show >/dev/null 2>&1; then
  echo "Error: Azure CLI is not logged in. Run 'az login' first." >&2
  exit 1
fi

if [[ -n "$SUBSCRIPTION" ]]; then
  az account set --subscription "$SUBSCRIPTION"
fi

mkdir -p "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR"

PRIVATE_KEY_PATH="$OUTPUT_DIR/$KEY_NAME"
PUBLIC_KEY_PATH="$OUTPUT_DIR/$KEY_NAME.pub"

# Always remove generated local key files when the script exits.
trap cleanup_keys EXIT

if [[ "$FORCE" != "true" && ( -e "$PRIVATE_KEY_PATH" || -e "$PUBLIC_KEY_PATH" ) ]]; then
  echo "Error: key file already exists at '$PRIVATE_KEY_PATH' (use --force to overwrite)." >&2
  exit 1
fi

if [[ "$FORCE" == "true" ]]; then
  rm -f "$PRIVATE_KEY_PATH" "$PUBLIC_KEY_PATH"
fi

echo "Generating RSA-4096 SSH key pair at '$PRIVATE_KEY_PATH'..."
ssh-keygen -t rsa -b 4096 -m PEM -C "$KEY_NAME" -f "$PRIVATE_KEY_PATH" -N "$PASSPHRASE" >/dev/null

chmod 600 "$PRIVATE_KEY_PATH"
chmod 644 "$PUBLIC_KEY_PATH"

echo "Uploading public key to Key Vault secret '$PUBLIC_SECRET_NAME'..."
az keyvault secret set \
  --vault-name "$KEYVAULT_NAME" \
  --name "$PUBLIC_SECRET_NAME" \
  --value "$(cat "$PUBLIC_KEY_PATH")" \
  --only-show-errors \
  --output none

echo "Uploading private key to Key Vault secret '$PRIVATE_SECRET_NAME'..."
az keyvault secret set \
  --vault-name "$KEYVAULT_NAME" \
  --name "$PRIVATE_SECRET_NAME" \
  --file "$PRIVATE_KEY_PATH" \
  --encoding utf-8 \
  --only-show-errors \
  --output none

echo "Done."
echo "- KV public key secret:  $PUBLIC_SECRET_NAME"
echo "- KV private key secret: $PRIVATE_SECRET_NAME"
echo "- Local generated key files were deleted after upload."
echo
echo "If Terraform reads the public key from Key Vault, set it to use secret '$PUBLIC_SECRET_NAME'."
