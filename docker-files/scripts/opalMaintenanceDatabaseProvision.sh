#!/usr/bin/env bash
set -euo pipefail

if [ -z "${BASE_DIR:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  BASE_DIR="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
fi

PROJECT="opal-stack"
MAX_ATTEMPTS="${OPAL_DB_READY_MAX_ATTEMPTS:-30}"
INTERVAL_SECONDS="${OPAL_DB_READY_INTERVAL_SECONDS:-2}"
DATABASE_NAME="opal-maintenance-db"
DATABASE_USER="${POSTGRES_USER:-opal-db-user}"

usage() {
  cat <<'USAGE'
Usage: opalMaintenanceDatabaseProvision [--project <name>]

Starts the shared PostgreSQL service and creates opal-maintenance-db when it is absent.

--project, -p     Docker Compose project name (default: opal-stack)

Set OPAL_DB_READY_MAX_ATTEMPTS and OPAL_DB_READY_INTERVAL_SECONDS to configure
the bounded PostgreSQL readiness wait.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

if ! [[ "$MAX_ATTEMPTS" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid OPAL_DB_READY_MAX_ATTEMPTS: $MAX_ATTEMPTS (must be a positive integer)" >&2
  exit 2
fi

if ! [[ "$INTERVAL_SECONDS" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "Invalid OPAL_DB_READY_INTERVAL_SECONDS: $INTERVAL_SECONDS (must be a non-negative number)" >&2
  exit 2
fi

COMPOSE_FILE="$BASE_DIR/opal-shared-infrastructure/docker-compose-maintenance.yml"
COMPOSE_COMMAND=(docker compose -p "$PROJECT" -f "$COMPOSE_FILE")

if ! "${COMPOSE_COMMAND[@]}" up -d --no-deps opal-db; then
  echo "Failed to start the shared opal-db service." >&2
  exit 1
fi

for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
  if database_exists="$(
    "${COMPOSE_COMMAND[@]}" exec -T opal-db \
      psql --username "$DATABASE_USER" --dbname postgres --tuples-only --no-align \
      --command "SELECT 1 FROM pg_database WHERE datname = '$DATABASE_NAME';" 2>/dev/null
  )"; then
    case "$database_exists" in
      1)
        echo "Database $DATABASE_NAME already exists."
        exit 0
        ;;
      "")
        if ! "${COMPOSE_COMMAND[@]}" exec -T opal-db \
          createdb --username "$DATABASE_USER" --maintenance-db postgres "$DATABASE_NAME"; then
          echo "Failed to create database $DATABASE_NAME." >&2
          exit 1
        fi

        echo "Created database $DATABASE_NAME."
        exit 0
        ;;
      *)
        echo "Unexpected response while checking for database $DATABASE_NAME: $database_exists" >&2
        exit 1
        ;;
    esac
  fi

  if ((attempt < MAX_ATTEMPTS)); then
    sleep "$INTERVAL_SECONDS"
  fi
done

echo "Timed out waiting for PostgreSQL after $MAX_ATTEMPTS attempts." >&2
exit 1
