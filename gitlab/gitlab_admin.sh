#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2022 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# GitLab admin functions

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'
SCRIPT_FOLDER="$(dirname "$(readlink -f "${0}")")"

if [[ ! -f "${SCRIPT_FOLDER}/../.localconfig" ]]; then
  echo "ERROR: File '$(readlink -f "${SCRIPT_FOLDER}/../.localconfig")' does not exists"
  echo "Create one to configure the location of the GitLab token. Example:"
  echo '{"gitlab-token": "SUPER_SECRET_TOKEN"}'
fi

PERSONAL_ACCESS_TOKEN="$(jq -r '."gitlab-token"' < "${SCRIPT_FOLDER}/../.localconfig")"
TOKEN_HEADER="PRIVATE-TOKEN: ${PERSONAL_ACCESS_TOKEN}"
API_BASE_URL="${API_BASE_URL:-"https://gitlab.eclipse.org/api/v4"}"

_check_parameter() {
  local param_name="${1:-}"
  local param="${2:-}"
  # check that parameter is not empty
  if [[ -z "${param}" ]]; then
    printf "ERROR: a %s must be given.\n" "${param_name}"
    exit 1
  fi
}

#TODO extract curl call

_add_user_to_group_api() {
  local group_id="${1:-}"
  local user_id="${2:-}"
  local access_level="${3:-}"

  curl -sSL --header "${TOKEN_HEADER}" --request POST "${API_BASE_URL}/groups/${group_id}/members" --data "user_id=${user_id}" --data "access_level=${access_level}"
}

_add_ssh_key_api() {
  local id="${1:-}"
  local title="${2:-}"
  local key="${3:-}"

  curl -sSL --header "${TOKEN_HEADER}" --request POST "${API_BASE_URL}/users/${id}/keys" --data-urlencode "title=${title}" --data-urlencode "key=${key}"
}

_create_user_api() {
  local username="${1:-}"
  local pw="${2:-}"
  local email="${3:-}"
  local name="${4:-}" #display name

  curl -sSL --header "${TOKEN_HEADER}" --request POST "${API_BASE_URL}/users" --data "username=${username}" --data "password=${pw}" --data "email=${email}" --data "name=${name}"
}

_create_webhook_api() {
  local repo_id="${1:-}"
  local hook_url="${2:-}"
  local hook_secret="${3:-}"

  #default trigger events: push, tag push, comments (note events), merge requests
  curl -sSL --header "${TOKEN_HEADER}" --request POST "${API_BASE_URL}/projects/${repo_id}/hooks" --data "url=${hook_url}" --data "token=${hook_secret}" --data "push_events=true" --data "tag_push_events=true" --data "note_events=true" --data "merge_requests_events=true"
}

_get_id_from_username() {
  local username="${1:-}"
  curl -s --header "${TOKEN_HEADER}" "${API_BASE_URL}/users?username=${username}" | jq -r '.[].id'
}

_get_project_id() {
  local repo_name="${1:-}"
  curl -s --header "${TOKEN_HEADER}" "${API_BASE_URL}/projects?search=${repo_name}" | jq -r '.[] | select(.path_with_namespace | startswith("eclipse/")) | .id'
}

_get_group_id() {
  local groupname="${1:-}"
  curl -s --header "${TOKEN_HEADER}" "${API_BASE_URL}/groups?search=${groupname}" | jq -r '.[].id'
}

help() {
  printf "Available commands:\n"
  printf "Command\t\t\tDescription\n\n"
  printf "add_ssh_key\t\tAdd SSH public key.\n"
  printf "add_user_to_group\tAdd user to group.\n"
  printf "create_api_token\tCreate API token.\n"
  printf "create_bot_user\t\tCreate GitLab bot user.\n"
  printf "create_webhook\t\tCreate webhook.\n"
  exit 0
}

#### commands
add_ssh_key() {
  # get ID
  local username="${1:-}"
  local id_rsa_pub="${2:-}"
  _check_parameter "username" "${username}"
  _check_parameter "SSH public key" "${id_rsa_pub}"
  
  local user_id
  user_id="$(_get_id_from_username "${username}")"

  # if SSH key already exists, skip
  if curl -sSL --header "${TOKEN_HEADER}" "${API_BASE_URL}/users/${user_id}/keys" | jq -e '.|length > 0' > /dev/null; then
    echo "SSH key already exists. Skipping creation..."
  else
    echo "Creating SSH key for ${username}..."
    _add_ssh_key_api "${user_id}" "${username}" "${id_rsa_pub}" | jq .
  fi
}

add_user_to_group() {
  local groupname="${1:-}"
  local username="${2:-}"
  local access_level="${3:-}" # 0 = no access, 5 = minimal access, 10 = Guest, 20 = Reporter, 30 = Developer, 40 = Maintainer, 50 = Owner
  _check_parameter "groupname" "${groupname}"
  _check_parameter "username" "${username}"
  _check_parameter "access level" "${access_level}"

  local user_id
  user_id="$(_get_id_from_username "${username}")"
  local group_id
  group_id="$(_get_group_id "${groupname}")"


  _add_user_to_group_api "${group_id}" "${user_id}" "${access_level}" | jq .
}

create_api_token() {
  # create impersonation token
  local username="${1:-}"
  _check_parameter "username" "${username}"
  local user_id
  user_id="$(_get_id_from_username "${username}")"
  local name="CI token"

  local token
  token="$(curl -sSL --header "${TOKEN_HEADER}" --request POST "${API_BASE_URL}/users/${user_id}/impersonation_tokens" --data-urlencode "name=${name}" --data "scopes[]=api" | jq -r .token 1>&2) "
  echo "${token}"
}

create_bot_user() {
  local project_name="${1:-}"
  local username="${2:-}"
  local pw="${3:-}"
  _check_parameter "project name" "${project_name}"
  _check_parameter "username" "${username}"
  _check_parameter "password" "${pw}"
  
  local email="${username}@eclipse.org"
  local short_name="${project_name##*.}"
  local name="${short_name} bot user"

  # if bot user already exists, skip
  if  curl -sSL --header "${TOKEN_HEADER}" "${API_BASE_URL}/users?username=${username}" | jq -e '.|length > 0' > /dev/null; then
    echo "User ${username} already exists. Skipping creation..."
  else
    echo "Creating bot user ${username}..."
    _create_user_api "${username}" "${pw}" "${email}" "${name}" | jq .
  fi
}

create_webhook() {
  local repo_name="${1:-}"
  local hook_url="${2:-}"
  local hook_secret="${3:-}"
  _check_parameter "repo name" "${repo_name}"
  _check_parameter "webhook URL" "${hook_url}"
  _check_parameter "webhook secret" "${hook_secret}"
  local repo_id
  repo_id="$(_get_project_id "${repo_name}")"

  # if webhook already exists, skip
#TODO: this assumes that only one webhook per repo is set
  if  curl -sSL --header "${TOKEN_HEADER}" "${API_BASE_URL}/projects/${repo_id}/hooks" | jq -e '.|length > 0' > /dev/null; then
    echo "Webhook for repo '${repo_name}' already exists. Skipping creation..."
  else
    create_webhook_api "${repo_id}" "${hook_url}" "${hook_secret}" | jq .
  fi
}


"$@"

# show help menu, if no first parameter is given
if [[ -z "${1:-}" ]]; then
  help
fi