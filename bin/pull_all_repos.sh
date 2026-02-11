#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/../../" && pwd)"

REPOS=(
  opal-fines-service
  opal-user-service
  opal-logging-service
  opal-shared-infrastructure
)

GIT_BASE_URL="https://github.com/hmcts"

echo
echo "Base directory: '${BASE_DIR}'"
echo

missing_repos=()

for repo in "${REPOS[@]}"; do
  repo_path="${BASE_DIR}/${repo}"

  if [[ -d "${repo_path}" ]]; then
    echo "✔ ${repo} already exists at ${repo_path}"
  else
    echo "✖ ${repo} missing → will clone to ${repo_path}"
    missing_repos+=("${repo}")
  fi
done

echo

if [[ "${#missing_repos[@]}" -eq 0 ]]; then
  echo "All repositories are present. Nothing to do."
  exit 0
fi


read -r -p "Proceed with cloning these repositories? [y/N] " confirm

case "${confirm}" in
  [yY]|[yY][eE][sS])
    echo "Proceeding…"
    ;;
  *)
    echo "Aborted."
    exit 0
    ;;
esac

for repo in "${missing_repos[@]}"; do
  repo_path="${BASE_DIR}/${repo}"
  echo "⬇ Cloning ${repo} into ${repo_path}"
  git clone --branch master "${GIT_BASE_URL}/${repo}.git" "${repo_path}"
done
