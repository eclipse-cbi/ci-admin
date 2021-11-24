#!/bin/bash
#*******************************************************************************
# Copyright (c) 2021 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# This script allows to list, add and delete GitHub organization secrets
# See also: https://docs.github.com/en/rest/reference/actions#secrets

# Requires encrypt_secret.js, Node.js and NPM
# Run 'npm install' to install Node.js dependencies

#TODO: do not pass secret/key/key_id as parameters
#TODO: escape special characters in secret
#TODO: handle multiline secrets gracefully
#TODO: deal with repo secrets

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'
SCRIPT_FOLDER="$(dirname "$(readlink -f "${0}")")"

if [[ ! -f "${SCRIPT_FOLDER}/../.localconfig" ]]; then
  echo "ERROR: File '$(readlink -f "${SCRIPT_FOLDER}/../.localconfig")' does not exists"
  echo "Create one to configure the location of the password store. Example:"
  echo '{"github": {"access_token": "SECRETTOKEN"}}'
fi
ACCESS_TOKEN="$(jq -r '.["github"]["access_token"]' "${SCRIPT_FOLDER}/../.localconfig")"

response="$(mktemp)"

_api_call() {
  local github_org="${1:-}"
  local api_path="${2:-}"
  local method="${3:-}"
  local json="${4:-}"
  local base_url="https://api.github.com/orgs/${github_org}"
  local credentials='-H "Authorization: token '${ACCESS_TOKEN}''

  curl -K- -X "${method}" "https://api.github.com/orgs/${github_org}/actions/secrets" -o "${response}" -s -w "%{http_code}" <<< ${credentials}
}

# returns JSON object with key_id and public key
_get_org_pub_key() {
  local github_org="${1:-}"

  response_code="$(_api_call "${github_org}" "actions/secrets/public-key" "GET")"
  if [[ $response_code -ne 200 ]]; then
    >&2 printf "ERROR while getting public key for organization %s (response code: %s).\n" "${github_org}" "${response_code}"
    >&2 cat "${response}"
    rm "${response}"
    exit 1
  else
    cat "${response}"
    rm "${response}"
  fi
}

help() {
  printf "Available commands:\n"
  printf "Command\t\t\tDescription\n\n"
  printf "list_org_secret(s)\tList organization secrets.\n"
  printf "add_org_secret\t\tAdd or update organization secret.\n"
  printf "delete_org_secret\tDelete organization secret.\n"
  exit 0
}

list_org_secret() {
  list_org_secrets "$@"
}

list_org_secrets() {
  local github_org="${1:-}"
  if [[ -z "${github_org}" ]]; then
    >&2 printf "ERROR: a GitHub organization must be given.\n"
    exit 1
  fi

  response_code="$(_api_call "${github_org}" "actions/secrets" "GET")"
  if [[ $response_code -ne 200 ]]; then
    >&2 printf "ERROR while getting list of secrets for organization %s (response code: %s).\n" "${github_org}" "${response_code}"
    >&2 cat "${response}"
    rm "${response}"
    exit 1
  else
    echo "Existing secrets in organization ${github_org}:"
    jq -r .secrets[].name "${response}"
    rm "${response}"
  fi
}

add_org_secret() {
  local github_org="${1:-}"
  local secret_name="${2:-}"
  #TODO: read from stdin
  local secret="${3:-}"

  if [[ -z "${github_org}" ]]; then
    >&2 printf "ERROR: a GitHub organization must be given.\n"
    exit 1
  fi

  if [[ -z "${secret_name}" ]]; then
    >&2 printf "ERROR: a secret name must be given.\n"
    exit 1
  fi

  if [[ -z "${secret}" ]]; then
    >&2 printf "ERROR: a secret must be given.\n"
    exit 1
  fi

  if [[ "${github_org}" == "eclipse" ]]; then
    >&2 printf "ERROR: a secret can not be added, since multiple project use the eclipse organization. Please specify a different organization.\n"
    exit 1
  fi

  json_response="$(_get_org_pub_key "${github_org}")"
  key_id="$(echo "${json_response}" | jq -r .key_id)"
  public_key="$(echo "${json_response}" | jq -r .key)"

  #TODO: is there a better way to do this?
  #encrypt with libsodium
  encrypted_value="$(node encrypt_secret.js "${public_key}" "${secret}")"
  json='{"visibility":"all","key_id":"'${key_id}'","encrypted_value":"'${encrypted_value}'"}'

  response_code="$(_api_call "${github_org}" "actions/secrets/${secret_name}" "PUT" "${json}")"

  if [[ "${response_code}" -eq 201 ]]; then
    echo "Secret ${secret_name} created in organization ${github_org}."
    #no content
  elif [[ "${response_code}" -eq 204 ]]; then
    echo "Secret ${secret_name} updated in organization ${github_org}."
    #no content
  else
    >&2 printf "ERROR while creating/updating secret ${secret_name} for organization %s (response code: %s).\n" "${github_org}" "${response_code}"
    >&2 cat "${response}"
    rm "${response}"
    exit 1
  fi
}

delete_org_secret() {
  local github_org="${1:-}"
  local secret_name="${2:-}"

  if [[ -z "${github_org}" ]]; then
    >&2 printf "ERROR: a GitHub organization must be given.\n"
    exit 1
  fi

  if [[ -z "${secret_name}" ]]; then
    >&2 printf "ERROR: a secret name must be given.\n"
    exit 1
  fi

  if [[ "${github_org}" == "eclipse" ]]; then
    >&2 printf "ERROR: a secret can not be deleted, since multiple project use the eclipse organization. Please specify a different organization.\n"
    exit 1
  fi

  response_code="$(_api_call "${github_org}" "actions/secrets/${secret_name}" "DELETE")"
  if [[ $response_code -ne 204 ]]; then
    >&2 printf "ERROR while deleting secret in organization %s (response code: %s).\n" "${github_org}" "${response_code}"
    >&2 cat "${response}"
    rm "${response}"
    exit 1
  else
    echo "Secret ${secret_name} deleted in organization ${github_org}."
    #no content
  fi
}

"$@"

# show help menu, if no first parameter is given
if [[ -z "${1:-}" ]]; then
  help
fi