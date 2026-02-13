#!/usr/bin/env bash
set -euo pipefail

if [ -z "${BASE_DIR:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  BASE_DIR="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
fi

PROJECT="opal-stack"
REMOVE_IMAGE=true
RUN_GRADLE=true
BRANCH=""

usage() {
  cat <<'USAGE'
Usage: opalUserRebuild [--branch <name>] [--keep-image] [--skip-gradle] [--project <name>]

Stops and removes only the opal-user-service container, optionally removes the image,
rebuilds the service, and starts it again.

--branch, -b      Switch opal-user-service to this git branch before building
--keep-image      Do not remove the local opal-user-service image
--skip-gradle     Skip ./gradlew clean assemble
--project, -p     Docker Compose project name (default: opal-stack)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch|-b)
      BRANCH="${2:-}"
      if [[ -z "$BRANCH" ]]; then
        echo "Missing branch name" >&2
        usage >&2
        exit 2
      fi
      shift 2
      ;;
    --keep-image)
      REMOVE_IMAGE=false
      shift
      ;;
    --skip-gradle)
      RUN_GRADLE=false
      shift
      ;;
    --project|-p)
      PROJECT="${2:-}"
      if [[ -z "$PROJECT" ]]; then
        echo "Missing project name" >&2
        usage >&2
        exit 2
      fi
      shift 2
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
done

if [[ ! -d "$BASE_DIR/opal-user-service" ]]; then
  echo "opal-user-service directory not found: $BASE_DIR/opal-user-service" >&2
  exit 1
fi

COMPOSE_FILES=(
  -f "$BASE_DIR/opal-user-service/docker-compose.base.yml"
  -f "$BASE_DIR/opal-user-service/docker-compose.local.yml"
)

docker compose -p "$PROJECT" \
  "${COMPOSE_FILES[@]}" \
  stop opal-user-service || true

docker compose -p "$PROJECT" \
  "${COMPOSE_FILES[@]}" \
  rm -f opal-user-service || true

if [[ "$REMOVE_IMAGE" == "true" ]]; then
  docker image rm opal-user-service:local || true
fi

if [[ -n "$BRANCH" ]]; then
  (cd "$BASE_DIR/opal-user-service" && git switch "$BRANCH")
fi

if [[ "$RUN_GRADLE" == "true" ]]; then
  (cd "$BASE_DIR/opal-user-service" && ./gradlew clean assemble)
fi

docker compose -p "$PROJECT" \
  "${COMPOSE_FILES[@]}" \
  up --build -d opal-user-service
