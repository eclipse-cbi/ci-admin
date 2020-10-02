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
script_name="$(basename ${0})"
script_folder="$(dirname $(readlink -f "${0}"))"

export password_store_dir=~/.password-store/cbi-pass
gitlab_pass_domain="gitlab.eclipse.org"


personal_access_token=$(cat ../.localconfig | jq -r '."gitlab-token"')
token_header="PRIVATE-TOKEN: ${personal_access_token}"
api_base_url="https://gitlab.eclipse.org/api/v4"

project_name=${1:-}

# verify input
if [ -z "${project_name}" ]; then
  printf "ERROR: a project name (e.g. 'technology.cbi' for CBI project) must be given.\n"
  exit 1
fi

pw_store_path="cbi-pass/bots/${project_name}/${gitlab_pass_domain}"
short_name="${project_name##*.}"

## GitLab API ##

add_user_api() {
  local username=$1
  local email=$2
  local pw=$3
  local name=$4 #display name

  curl -s --header "${token_header}" --request POST "${api_base_url}/users" --data "username=${username}" --data "email=${email}" --data "password=${pw}" --data "name=${name}" | jq .
}

add_ssh_key_api() {
  local id=$1
  local title=$2
  local key=$3

  curl -s --header "${token_header}" --request POST "${api_base_url}/users/${id}/keys" --data-urlencode "title=${title}" --data-urlencode "key=${key}" | jq .
}


create_credentials_in_pass() {
  if [[ ! -f "${password_store_dir}/bots/${project_name}/${gitlab_pass_domain}/id_rsa.gpg" ]]; then
    echo "Creating GitLab SSH credentials in SSH..."
    pushd "${script_folder}/.."
    ./add_creds_ssh.sh "${project_name}" "${gitlab_pass_domain}" "${short_name}-bot"
    popd
    # create password
    pwgen -1 -s -y 24 | pass insert --echo "${pw_store_path}/password"
  else
    echo "Found ${gitlab_pass_domain} SSH credentials in password store. Skipping creation..."
  fi
}

create_bot_user() {
  local username=$(pass "${pw_store_path}/username")
  local email="${username}@eclipse.org"
  local pw=$(pass "${pw_store_path}/password")
  local name="${short_name} bot user"

   # if bot user already exists, skip
  if [ "$(curl -s --header "${token_header}" "${api_base_url}/users?username=${username}" | jq .)" == "[]" ]; then
    echo "Creating bot user ${username}..."
    add_user_api "${username}" "${email}" "${pw}" "${name}"
  else
    echo "User ${username} already exists. Skipping creation..."
  fi
}

get_id_from_username() {
  local username=$(pass "${pw_store_path}/username")
  curl -s --header "${token_header}" "${api_base_url}/users?username=${username}" | jq '.[].id'
}

add_ssh_key() {
  # get ID
  local user_id=$(get_id_from_username)

  # if SSH key already exists, skip
  if [ "$(curl -s --header "${token_header}" "${api_base_url}/users/${user_id}/keys" | jq .)" == "[]" ]; then
    echo "Creating SSH key for ${username}..."
    # read ssh public key from pass
    id_rsa_pub=$(pass "${pw_store_path}/id_rsa.pub")
    add_ssh_key_api "${id}" "${username}" "${id_rsa_pub}"
  else
    echo "SSH key already exists. Skipping creation..."
  fi
}

# create impersonation token
create_api_token() {
  # get ID
  local user_id=$(get_id_from_username)

  name="CI token"
  printf "API token: "
  curl -s --header "${token_header}" --request POST "${api_base_url}/users/${user_id}/impersonation_tokens" --data-urlencode "name=${name}" --data "scopes[]=read_api" | jq -r .token
}

# MAIN

create_credentials_in_pass
create_bot_user
add_ssh_key
create_api_token

echo "Done."

