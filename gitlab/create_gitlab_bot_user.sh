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
SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

source "${SCRIPT_FOLDER}/pass_wrapper.sh"

GITLAB_PASS_DOMAIN="gitlab.eclipse.org"

PROJECT_NAME="${1:-}"

# verify input
if [ -z "${PROJECT_NAME}" ]; then
  printf "ERROR: a project name (e.g. 'technology.cbi' for CBI project) must be given.\n"
  exit 1
fi

PW_STORE_PATH="bots/${PROJECT_NAME}/${GITLAB_PASS_DOMAIN}"


create_credentials_in_pass() {
  local project_name="${1:-}"
  local short_name="${project_name##*.}"

#TODO: simplify
  if ! passw cbi "${PW_STORE_PATH}/id_rsa" &> /dev/null ; then
    echo "Creating GitLab SSH credentials in password store..."
    "${SCRIPT_FOLDER}/../pass/add_creds.sh" "ssh_keys" "${project_name}" "${GITLAB_PASS_DOMAIN}" "${short_name}-bot"
    # create password (password parameter is required by GitLab API), could be replaced with "force_random_password" API option
    pwgen -1 -s -r '&' -y 24 | passw cbi insert --echo "${PW_STORE_PATH}/password"
  else
    echo "Found ${GITLAB_PASS_DOMAIN} SSH credentials in password store. Skipping creation..."
  fi
}

# MAIN

create_credentials_in_pass "${PROJECT_NAME}"

username="$(passw cbi "${PW_STORE_PATH}/username")"
pw="$(passw cbi "${PW_STORE_PATH}/password")"
id_rsa_pub="$(passw cbi "${PW_STORE_PATH}/id_rsa.pub")"

"${SCRIPT_FOLDER}/gitlab_admin.sh" "create_bot_user" "${PROJECT_NAME}" "${username}" "${pw}"

"${SCRIPT_FOLDER}/gitlab_admin.sh" "add_ssh_key" "${username}" "${id_rsa_pub}"

#TODO: check if api-token already exists
token="$("${SCRIPT_FOLDER}/gitlab_admin.sh" "create_api_token" "${username}")"
echo "Adding API token to pass..."
echo "${token}" | passw cbi insert --echo "${PW_STORE_PATH}/api-token"

echo "Done."

