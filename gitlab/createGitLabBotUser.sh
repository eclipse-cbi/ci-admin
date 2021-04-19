#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2020 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Create bot user in GitLab and set up SSH key

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'
SCRIPT_NAME="$(basename "${0}")"
SCRIPT_FOLDER="$(dirname $(readlink -f "${0}"))"

if [[ ! -f "${SCRIPT_FOLDER}/../.localconfig" ]]; then
  echo "ERROR: File '$(readlink -f "${SCRIPT_FOLDER}/../.localconfig")' does not exists"
  echo "Create one to configure the location of the password store. Example:"
  echo '{"password-store": {"cbi-dir": "~/.password-store/cbi"}}'
fi
PASSWORD_STORE_DIR="$(jq -r '.["password-store"]["cbi-dir"]' "${SCRIPT_FOLDER}/../.localconfig")"
PASSWORD_STORE_DIR="$(readlink -f "${PASSWORD_STORE_DIR/#~\//${HOME}/}")"
export PASSWORD_STORE_DIR

GITLAB_PASS_DOMAIN="gitlab.eclipse.org"

PERSONAL_ACCESS_TOKEN="$(cat "${SCRIPT_FOLDER}/../.localconfig" | jq -r '."gitlab-token"')"
TOKEN_HEADER="PRIVATE-TOKEN: ${PERSONAL_ACCESS_TOKEN}"
API_BASE_URL="${API_BASE_URL:-"https://gitlab.eclipse.org/api/v4"}"

PROJECT_NAME="${1:-}"

# verify input
if [ -z "${PROJECT_NAME}" ]; then
  printf "ERROR: a project name (e.g. 'technology.cbi' for CBI project) must be given.\n"
  exit 1
fi

PW_STORE_PATH="bots/${PROJECT_NAME}/${GITLAB_PASS_DOMAIN}"
SHORT_NAME="${PROJECT_NAME##*.}"

## GitLab API ##

add_user_api() {
  local username="$1"
  local pw="$2"
  local email="$3"
  local name="$4" #display name

  curl -sSL --header "${TOKEN_HEADER}" --request POST "${API_BASE_URL}/users" --data "username=${username}" --data "password=${pw}" --data "email=${email}" --data "name=${name}"
}

add_ssh_key_api() {
  local id="$1"
  local title="$2"
  local key="$3"

  curl -sSL --header "${TOKEN_HEADER}" --request POST "${API_BASE_URL}/users/${id}/keys" --data-urlencode "title=${title}" --data-urlencode "key=${key}"
}


create_credentials_in_pass() {
  local project_name="$1"
  if [[ ! -f "${PASSWORD_STORE_DIR}/bots/${project_name}/${GITLAB_PASS_DOMAIN}/id_rsa.gpg" ]]; then
    echo "Creating GitLab SSH credentials in SSH..."
    "${SCRIPT_FOLDER}/../add_creds_ssh.sh" "${project_name}" "${GITLAB_PASS_DOMAIN}" "${SHORT_NAME}-bot"
    # create password
    pwgen -1 -s -y 24 | pass insert --echo "${PW_STORE_PATH}/password"
  else
    echo "Found ${GITLAB_PASS_DOMAIN} SSH credentials in password store. Skipping creation..."
  fi
}

create_bot_user() {
  local username="$1"
  local pw="$2"
  local email="${username}@eclipse.org"
  local name="${SHORT_NAME} bot user"

   # if bot user already exists, skip
  if  curl -sSL --header "${TOKEN_HEADER}" "${API_BASE_URL}/users?username=${username}" | jq -e '.|length > 0' > /dev/null; then
    echo "User ${username} already exists. Skipping creation..."
  else
    echo "Creating bot user ${username}..."
    add_user_api "${username}" "${pw}" "${email}" "${name}"  | jq .
  fi
}

get_id_from_username() {
  local username="$1"
  curl -s --header "${TOKEN_HEADER}" "${API_BASE_URL}/users?username=${username}" | jq -r '.[].id'
}

add_ssh_key() {
  # get ID
  local username="$1"
  local user_id
  user_id="$(get_id_from_username "${username}")"

  # if SSH key already exists, skip
  if curl -sSL --header "${TOKEN_HEADER}" "${API_BASE_URL}/users/${user_id}/keys" | jq -e '.|length > 0' > /dev/null; then
    echo "SSH key already exists. Skipping creation..."
  else
    echo "Creating SSH key for ${username}..."
    # read ssh public key from pass
    local id_rsa_pub
    id_rsa_pub="$(pass "${PW_STORE_PATH}/id_rsa.pub")"
    add_ssh_key_api "${user_id}" "${username}" "${id_rsa_pub}" | jq .
  fi
}

# create impersonation token
create_api_token() {
  # get ID
  local username="$1"
  local user_id
  user_id="$(get_id_from_username "${username}")"
  local name="CI token"

  local token
  token="$(curl -sSL --header "${TOKEN_HEADER}" --request POST "${API_BASE_URL}/users/${user_id}/impersonation_tokens" --data-urlencode "name=${name}" --data "scopes[]=api" | jq -r .token)"
  echo "Adding API token to pass..."
  echo "${token}" | pass insert --echo "${PW_STORE_PATH}/api-token"
}

# MAIN


create_credentials_in_pass "${PROJECT_NAME}"

username="$(pass "${PW_STORE_PATH}/username")"
pw="$(pass "${PW_STORE_PATH}/password")"

create_bot_user "${username}" "${pw}"
add_ssh_key "${username}"
create_api_token "${username}"

echo "Done."

