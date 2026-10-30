#!/usr/bin/env bash
set -euo pipefail

if [ -z "${BASE_DIR:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  BASE_DIR="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
fi

PROJECT="${PROJECT:-opal-stack}"
SERVICE="opal-db"
VOLUME="${PROJECT}_opal-database-data"
COMPOSE_FILE="$BASE_DIR/opal-shared-infrastructure/docker-compose.yml"

usage() {
  cat <<'USAGE'
Usage: opalDbReset

Stops and removes only the shared Opal database container, deletes its data
volume, then starts the database container again.
USAGE
}

case "${1:-}" in
  "") ;;
  -h|--help) usage; exit 0 ;;
  *)
    echo "Unknown option: ${1}" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Docker compose file not found: $COMPOSE_FILE" >&2
  exit 1
fi

echo "Stopping $SERVICE..."
docker compose -p "$PROJECT" -f "$COMPOSE_FILE" stop "$SERVICE" || true

echo "Removing $SERVICE container..."
docker compose -p "$PROJECT" -f "$COMPOSE_FILE" rm -f "$SERVICE" || true

echo "Removing database volume $VOLUME..."
docker volume rm "$VOLUME" || true

echo "Starting $SERVICE..."
docker compose -p "$PROJECT" -f "$COMPOSE_FILE" up -d "$SERVICE"
