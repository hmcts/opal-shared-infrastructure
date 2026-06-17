#!/usr/bin/env bash
set -euo pipefail

if [ -z "${BASE_DIR:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  BASE_DIR="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
fi

acr_login() {
  local registry_name="hmctsprod"
  local subscription_name="DCD-CNP-Prod"
  local login_output

  if login_output="$(az acr login --name "$registry_name" --subscription "$subscription_name" 2>&1)"; then
    return 0
  fi

  echo "$login_output" >&2
  echo >&2
  echo "ACR login failed for $registry_name in $subscription_name." >&2
  echo "Ensure ZScaler Internet Security is Off" >&2
  exit 1
}

acr_login

MODE=""
SKIP_UPDATE=false
SKIP_CLEAN=false
MAX_PARALLEL="${MAX_PARALLEL:-2}"
INCLUDE_FRONTEND=false

usage() {
  cat <<'USAGE'

Usage: opalBuild [-localBranches|-lb|-localMaster|-lm|-c|-current] [-skipClean|-sc] [-j|--jobs <count>] [-frontend|-fe]

Recreate the Opal docker containers with optional git and .gradlew operations in each Opal repository.

-localBranches, -lb: fetch/pull current branches in each repo
-localMaster, -lm: checkout master, then fetch/pull in each repo
-current, -c: do not fetch/pull or change the current git repository state
-skipClean, -sc: build the docker compose without first performing a ./gradlew clean assemble
-j, --jobs: number of Gradle repositories to build in parallel (default: 2, or env MAX_PARALLEL)
-frontend, -fe: include the frontend repo and frontend docker compose services
USAGE
}

option_provided=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -localBranches|-lb)
	MODE="localBranches"
	option_provided=true
	;;
    -localMaster|-lm)
	MODE="localMaster"
	option_provided=true
	;;
    -current|-c)
	SKIP_UPDATE=true
	option_provided=true
	;;
    -skipClean|-sc)
	SKIP_CLEAN=true
	;;
    -j|--jobs)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for $1" >&2
        usage >&2
        exit 2
      fi
      MAX_PARALLEL="$2"
      shift
      ;;
    -frontend|-fe)
      INCLUDE_FRONTEND=true
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

if ! $option_provided; then
  echo "Error: You must specify at least one option related to which git branch to use." >&2
  usage >&2
  exit 1
fi


if [[ ! -d "$BASE_DIR" ]]; then
  echo "Base directory not found: $BASE_DIR" >&2
  exit 1
fi

cd "$BASE_DIR"

REPOS=(
  opal-fines-service
  opal-user-service
  opal-logging-service
  opal-shared-infrastructure
)

if [[ "$INCLUDE_FRONTEND" == "true" ]]; then
  REPOS+=(opal-frontend)
fi

for repo in "${REPOS[@]}"; do
  echo "Processing repo: $repo"
  if [[ ! -d "$repo" ]]; then
    echo "Missing repo: $BASE_DIR/$repo" >&2
    exit 1
  fi

  if [[ "$SKIP_UPDATE" == "false" ]]; then
    if [[ "$MODE" == "localMaster" ]]; then
      (cd "$repo" && git checkout master)
    fi
    (cd "$repo" && git fetch && git pull)
  fi
done

GRADLE_REPOS=(
  opal-fines-service
  opal-user-service
  opal-logging-service
)

if [[ "$SKIP_CLEAN" == "false" ]]; then
  if ! [[ "$MAX_PARALLEL" =~ ^[1-9][0-9]*$ ]]; then
    echo "Invalid parallel jobs value: $MAX_PARALLEL (must be a positive integer)" >&2
    exit 2
  fi

  printf '%s\0' "${GRADLE_REPOS[@]}" | xargs -0 -n 1 -P "$MAX_PARALLEL" bash -c '
    repo="$1"
    echo "Processing Building project: $repo"
    cd "$repo" && ./gradlew clean assemble
  ' _
fi

PROJECT=opal-stack

COMPOSE_FILES=(
  -f "$BASE_DIR/opal-fines-service/docker-compose.base.yml"
  -f "$BASE_DIR/opal-fines-service/docker-compose.local.yml"
  -f "$BASE_DIR/opal-user-service/docker-compose.base.yml"
  -f "$BASE_DIR/opal-user-service/docker-compose.local.yml"
  -f "$BASE_DIR/opal-logging-service/docker-compose.base.yml"
  -f "$BASE_DIR/opal-logging-service/docker-compose.local.yml"
)

if [[ "$INCLUDE_FRONTEND" == "true" ]]; then
  COMPOSE_FILES+=(
    -f "$BASE_DIR/opal-frontend/docker-compose.base.yml"
    -f "$BASE_DIR/opal-frontend/docker-compose.local.yml"
  )
fi

docker compose -p "$PROJECT" \
  "${COMPOSE_FILES[@]}" \
  up --build -d
