#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Generate SSH keys for the Bais emulator and install it
for local dev

Usage:
  . ./ssh/setup-bais-sftp-docker.sh

Optional:
  --help                       Show this help
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' was not found." >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'." >&2
      usage
      exit 1
      ;;
  esac
done

require_cmd ssh-keygen

REPO_ROOT="$(cd "$(pwd)/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
PUBLIC_KEY_PATH="$TEMP_DIR/bais-sftp-key.pub"
PRIVATE_KEY_PATH="$TEMP_DIR/bais-sftp-key"

trap 'rm -rf "$TEMP_DIR"' EXIT

ssh-keygen -t rsa -b 4096 -m PEM -C "bais-emulator" -f "$PRIVATE_KEY_PATH" -N "" >/dev/null

for user_name in BTEckoh-report CAPS-report AllPay NATWEST BARCLAYCARD; do
  key_dir="$REPO_ROOT/bais-emulator/data/$user_name/.ssh/keys"
  install -d -m 0755 "$key_dir"
  install -m 0644 "$PUBLIC_KEY_PATH" "$key_dir/bais-sftp-key.pub"
  install -m 0644 "$PRIVATE_KEY_PATH" "$key_dir/bais-sftp-key"

  echo "Installed public/private key for $user_name."
done

export BAIS_SFTP_PRIVATE_KEY="$(<"$PRIVATE_KEY_PATH")"

echo "Done."
