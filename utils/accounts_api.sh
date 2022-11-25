#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2022 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

TOKEN_URL="https://accounts.eclipse.org/oauth2/token"
PROFILE_URL="https://api.eclipse.org/account/profile"

SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../pass/pass_wrapper.sh"

_request_access_token() {
  local client_id client_secret
  client_id="$(passw cbi api.eclipse.org/client_id)"
  client_secret="$(passw cbi api.eclipse.org/client_secret)"
  curl -sSLf --request POST \
    --url "${TOKEN_URL}" \
    --header 'content-type: application/x-www-form-urlencoded' \
    --data 'grant_type=client_credentials' \
    --data "client_id=${client_id}" \
    --data "client_secret=${client_secret}" \
    --data 'scope=eclipsefdn_view_all_profiles' | jq -r '.access_token'
}

help() {
  printf "Available commands:\n"
  printf "Command\t\t\t\t\tDescription\n\n"
  printf "get_profile_by_user_id\t\t\tGet account profile by user ID.\n"
  exit 0
}

ACCESS_TOKEN="$(_request_access_token)"

get_profile_by_user_id() {
  local user_id="$1"
  curl -sLf --request GET \
    --retry 8 \
    --url "${PROFILE_URL}/${user_id}.json" \
    --header "Authorization: Bearer ${ACCESS_TOKEN}" | jq '.'
}

"$@"

# show help menu, if no first parameter is given
if [[ -z "${1:-}" ]]; then
  help
fi

