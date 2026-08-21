#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROVISION_SCRIPT="${SCRIPTS_DIR}/opalMaintenanceDatabaseProvision.sh"
BUILD_SCRIPT="${SCRIPTS_DIR}/opalBuild.sh"
REBUILD_SCRIPT="${SCRIPTS_DIR}/opalMaintenanceRebuild.sh"

[[ -x "$PROVISION_SCRIPT" ]] || {
  echo "FAIL: Provisioning helper is missing or not executable: $PROVISION_SCRIPT" >&2
  exit 1
}

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"

  grep -Fq -- "$expected" "$file" || fail "Expected $file to contain: $expected"
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"

  if grep -Fq -- "$unexpected" "$file"; then
    fail "Expected $file not to contain: $unexpected"
  fi
}

assert_count() {
  local file="$1"
  local expected_count="$2"
  local pattern="$3"
  local actual_count

  actual_count="$(grep -Fc -- "$pattern" "$file" || true)"
  [[ "$actual_count" == "$expected_count" ]] ||
    fail "Expected $expected_count occurrences of '$pattern' in $file, found $actual_count"
}

create_mock_commands() {
  local fixture_dir="$1"
  local mock_bin="${fixture_dir}/bin"

  mkdir -p "$mock_bin"

  cat > "${mock_bin}/docker" <<'MOCK_DOCKER'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$MOCK_DOCKER_LOG"

if [[ "$*" == *"exec -T opal-db psql"* ]]; then
  case "${MOCK_DB_STATE:-present}" in
    present)
      echo "1"
      ;;
    absent)
      ;;
    timeout)
      exit 1
      ;;
    *)
      echo "Unknown MOCK_DB_STATE: ${MOCK_DB_STATE:-}" >&2
      exit 2
      ;;
  esac
fi
MOCK_DOCKER

  cat > "${mock_bin}/az" <<'MOCK_AZ'
#!/usr/bin/env bash
exit 0
MOCK_AZ

  chmod +x "${mock_bin}/docker" "${mock_bin}/az"
}

create_stack_fixture() {
  local fixture_dir="$1"
  local repo
  local repos=(
    opal-fines-service
    opal-user-service
    opal-logging-service
    opal-file-handler-service
    opal-maintenance-service
    opal-legacy-db-stub
    opal-shared-infrastructure
  )

  for repo in "${repos[@]}"; do
    mkdir -p "${fixture_dir}/${repo}"
  done

  mkdir -p "${fixture_dir}/opal-shared-infrastructure/docker-files/scripts"
  ln -s "$PROVISION_SCRIPT" \
    "${fixture_dir}/opal-shared-infrastructure/docker-files/scripts/opalMaintenanceDatabaseProvision.sh"
}

run_provision_script() {
  local fixture_dir="$1"
  local state="$2"
  local output_file="$3"

  PATH="${fixture_dir}/bin:${PATH}" \
    BASE_DIR="$fixture_dir" \
    MOCK_DOCKER_LOG="${fixture_dir}/docker.log" \
    MOCK_DB_STATE="$state" \
    OPAL_DB_READY_MAX_ATTEMPTS=3 \
    OPAL_DB_READY_INTERVAL_SECONDS=0 \
    "$PROVISION_SCRIPT" > "$output_file" 2>&1
}

test_database_already_present() {
  local fixture_dir="${TEST_ROOT}/present"
  local output_file="${fixture_dir}/output.log"

  mkdir -p "$fixture_dir"
  create_mock_commands "$fixture_dir"
  run_provision_script "$fixture_dir" present "$output_file"

  assert_contains "${fixture_dir}/docker.log" \
    "compose -p opal-stack -f ${fixture_dir}/opal-shared-infrastructure/docker-compose-maintenance.yml up -d --no-deps opal-db"
  assert_count "${fixture_dir}/docker.log" 1 "exec -T opal-db psql"
  assert_not_contains "${fixture_dir}/docker.log" "exec -T opal-db createdb"
  assert_contains "$output_file" "Database opal-maintenance-db already exists."
}

test_database_absent() {
  local fixture_dir="${TEST_ROOT}/absent"
  local output_file="${fixture_dir}/output.log"

  mkdir -p "$fixture_dir"
  create_mock_commands "$fixture_dir"
  run_provision_script "$fixture_dir" absent "$output_file"

  assert_count "${fixture_dir}/docker.log" 1 "exec -T opal-db createdb"
  assert_contains "$output_file" "Created database opal-maintenance-db."
}

test_postgres_timeout_is_bounded() {
  local fixture_dir="${TEST_ROOT}/timeout"
  local output_file="${fixture_dir}/output.log"
  local exit_code=0

  mkdir -p "$fixture_dir"
  create_mock_commands "$fixture_dir"

  run_provision_script "$fixture_dir" timeout "$output_file" || exit_code=$?

  [[ "$exit_code" -ne 0 ]] || fail "Expected PostgreSQL timeout to exit non-zero"
  assert_count "${fixture_dir}/docker.log" 3 "exec -T opal-db psql"
  assert_not_contains "${fixture_dir}/docker.log" "exec -T opal-db createdb"
  assert_contains "$output_file" "Timed out waiting for PostgreSQL after 3 attempts."
}

test_opal_build_provisions_before_complete_stack_start() {
  local fixture_dir="${TEST_ROOT}/build"
  local output_file="${fixture_dir}/output.log"
  local provision_line
  local stack_line

  mkdir -p "$fixture_dir"
  create_mock_commands "$fixture_dir"
  create_stack_fixture "$fixture_dir"

  PATH="${fixture_dir}/bin:${PATH}" \
    BASE_DIR="$fixture_dir" \
    MOCK_DOCKER_LOG="${fixture_dir}/docker.log" \
    MOCK_DB_STATE=present \
    OPAL_DB_READY_MAX_ATTEMPTS=3 \
    OPAL_DB_READY_INTERVAL_SECONDS=0 \
    "$BUILD_SCRIPT" -c -sc > "$output_file" 2>&1

  provision_line="$(grep -nF "up -d --no-deps opal-db" "${fixture_dir}/docker.log" | cut -d: -f1)"
  stack_line="$(grep -nF "up --build -d" "${fixture_dir}/docker.log" | cut -d: -f1)"
  [[ "$provision_line" -lt "$stack_line" ]] || fail "Expected provisioning before complete stack start"
  assert_contains "${fixture_dir}/docker.log" \
    "compose -p opal-stack -f ${fixture_dir}/opal-shared-infrastructure/docker-compose-maintenance.yml up -d --no-deps opal-db"
  assert_contains "${fixture_dir}/docker.log" \
    "-f ${fixture_dir}/opal-shared-infrastructure/docker-compose-maintenance.yml up --build -d"
}

test_maintenance_rebuild_provisions_before_service_start() {
  local fixture_dir="${TEST_ROOT}/rebuild"
  local output_file="${fixture_dir}/output.log"
  local provision_line
  local service_line

  mkdir -p "$fixture_dir"
  create_mock_commands "$fixture_dir"
  create_stack_fixture "$fixture_dir"

  PATH="${fixture_dir}/bin:${PATH}" \
    BASE_DIR="$fixture_dir" \
    MOCK_DOCKER_LOG="${fixture_dir}/docker.log" \
    MOCK_DB_STATE=present \
    OPAL_DB_READY_MAX_ATTEMPTS=3 \
    OPAL_DB_READY_INTERVAL_SECONDS=0 \
    "$REBUILD_SCRIPT" --skip-gradle --keep-image --project test-stack > "$output_file" 2>&1

  provision_line="$(grep -nF "up -d --no-deps opal-db" "${fixture_dir}/docker.log" | cut -d: -f1)"
  service_line="$(grep -nF "up --build -d opal-maintenance-service" "${fixture_dir}/docker.log" | cut -d: -f1)"
  [[ "$provision_line" -lt "$service_line" ]] || fail "Expected provisioning before Maintenance Service start"
  assert_contains "${fixture_dir}/docker.log" \
    "compose -p test-stack -f ${fixture_dir}/opal-shared-infrastructure/docker-compose-maintenance.yml up -d --no-deps opal-db"
  assert_contains "${fixture_dir}/docker.log" \
    "compose -p test-stack -f ${fixture_dir}/opal-shared-infrastructure/docker-compose-maintenance.yml up --build -d opal-maintenance-service"
  assert_not_contains "${fixture_dir}/docker.log" "image rm opal-maintenance-service:local"
}

test_database_already_present
test_database_absent
test_postgres_timeout_is_bounded
test_opal_build_provisions_before_complete_stack_start
test_maintenance_rebuild_provisions_before_service_start

echo "PASS: Maintenance database provisioning and lifecycle integration"
