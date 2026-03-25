#!/usr/bin/env bash
set -euo pipefail

if [ -z "${BASE_DIR:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  BASE_DIR="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
fi

az acr login --name hmctsprod --subscription DCD-CNP-Prod

MODE=""
SKIP_UPDATE=false
SKIP_CLEAN=false

usage() {
  cat <<'USAGE'

Usage: opalBuild [-localBranches|-lb|-localMaster|-lm|-c|-current] [-skipClean|-sc]

Recreate the Opal docker containers with optional git and .gradlew operations in each Opal repository.

-localBranches, -lb: fetch/pull current branches in each repo
-localMaster, -lm: checkout master, then fetch/pull in each repo
-current, -c: do not fetch/pull or change the current git repository state
-skipClean, -sc: build the docker compose without first performing a ./gradlew clean assemble
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
  for repo in "${GRADLE_REPOS[@]}"; do
    echo "Processing Building project: $repo"
    (cd "$repo" && ./gradlew clean assemble)
  done
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

docker compose -p "$PROJECT" \
  "${COMPOSE_FILES[@]}" \
  up --build -d
