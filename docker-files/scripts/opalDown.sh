#!/usr/bin/env bash
set -euo pipefail

if [ -z "${BASE_DIR:-}" ]; then
  BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../"
fi
RESET=false
INCLUDE_FRONTEND=false


usage() {
  cat <<'USAGE'
Usage: opalDown [-r|--reset] [-fe|-frontend]

-r, --reset      Also delete volumes
-fe, -frontend   Also stop and remove the frontend
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--reset) RESET=true ;;
    -fe|-frontend) INCLUDE_FRONTEND=true ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ ! -d "$BASE_DIR" ]]; then
  echo "Base directory not found: $BASE_DIR" >&2
  exit 1
fi

cd "$BASE_DIR"

DOWN_ARGS=(down)
if [[ "$RESET" == "true" ]]; then
  DOWN_ARGS+=( -v )
fi

COMPOSE_FILES=(
  -f "$BASE_DIR/opal-fines-service/docker-compose.base.yml"
  -f "$BASE_DIR/opal-fines-service/docker-compose.local.yml"
  -f "$BASE_DIR/opal-user-service/docker-compose.base.yml"
  -f "$BASE_DIR/opal-user-service/docker-compose.local.yml"
  -f "$BASE_DIR/opal-logging-service/docker-compose.base.yml"
  -f "$BASE_DIR/opal-logging-service/docker-compose.local.yml"
  -f "$BASE_DIR/opal-legacy-db-stub/docker-compose.base.yml"
  -f "$BASE_DIR/opal-legacy-db-stub/docker-compose.local.yml"
  -f "$BASE_DIR/opal-file-handler-service/docker-compose.base.yml"
  -f "$BASE_DIR/opal-file-handler-service/docker-compose.local.yml"
  -f "$BASE_DIR/opal-maintenance-service/docker-compose.base.yml"
  -f "$BASE_DIR/opal-maintenance-service/docker-compose.local.yml"
)

if [[ "$INCLUDE_FRONTEND" == "true" ]]; then
  # The local file identifies the frontend for teardown. Its base file imports
  # backend services already loaded above, causing resource conflicts.
  COMPOSE_FILES+=(
    -f "$BASE_DIR/opal-frontend/docker-compose.local.yml"
  )
fi

PROJECT=opal-stack

docker compose -p "$PROJECT" \
  "${COMPOSE_FILES[@]}" \
  "${DOWN_ARGS[@]}" || true
