#!/usr/bin/env bash

#*******************************************************************************
# Copyright (c) 2026 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Transfer GitHub repos utilizing GitHub API
# API Documentation: https://docs.github.com/en/rest/repos/repos?apiVersion=2026-03-10#transfer-a-repository

# Either transfer a single repo
# Example: ./gh_transfer_repos.sh <source_gh_org> <target_gh_org> <repo>

# or multiple repos defined in repos.txt file
# Example: ./gh_transfer_repos.sh <source_gh_org> <target_gh_org>

# TODO: add support for specifiying target repo

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

BEARER_TOKEN="XXX" # classic token with scopes: "admin:org, repo"

OLD_ORG="${1:-}"
NEW_ORG="${2:-}"
SINGLE_REPO="${3:-}"
REPOS_FILE="repos.txt"

# check that old owner/org is not empty
if [[ -z "${OLD_ORG}" ]]; then
  printf "ERROR: name of source org must be given.\n"
  exit 1
fi

# check that old owner/org is not empty
if [[ -z "${NEW_ORG}" ]]; then
  printf "ERROR: name of target org must be given.\n"
  exit 1
fi

# check that repos.txt exist and is not empty if single repo parameter is not used
if [[ -z "${SINGLE_REPO}" ]] && [[ ! -f "${REPOS_FILE}" ]]; then
  printf "ERROR: %s is missing.\n" "${REPOS_FILE}"
  exit 1
fi


transfer_repo() {
  local old_owner="${1:-}"
  local old_repo_name="${2:-}"
  local new_owner="${3:-}"
  printf "Transferring %s..." "${old_owner}/${old_repo_name}"
  local response
  response="$(curl -sL \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${BEARER_TOKEN}" \
    -H "X-GitHub-Api-Version: 2026-03-10" \
    "https://api.github.com/repos/${old_owner}/${old_repo_name}/transfer" \
    -d '{"new_owner":"'"${new_owner}"'"}' | jq . )"

  if [[ "$(echo "${response}" | jq .message)" != "null" ]]; then
    printf "FAILED\n"
    echo "  ERROR:"
    printf "   Message: %s\n" "$(echo "${response}" | jq '.message')"
    if [[ "$(echo "${response}" | jq .errors)" != "null" ]]; then
      printf "   Errors/Message: %s\n" "$(echo "${response}" | jq '.errors[].message')"
    fi
    echo
  else
    printf "DONE\n\n"
  fi
}


if [[ -n "${SINGLE_REPO}" ]]; then
  transfer_repo "${OLD_ORG}" "${SINGLE_REPO}" "${NEW_ORG}"
else
  while read -r repo || [[ $repo ]]; do
    transfer_repo "${OLD_ORG}" "${repo}" "${NEW_ORG}"
  done < "${REPOS_FILE}"
fi

