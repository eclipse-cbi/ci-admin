#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2023 Eclipse Foundation and others.
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
LOCAL_CONFIG="${HOME}/.cbi/config"
SCRIPT_FOLDER="$(dirname "$(readlink -f "${0}")")"

if [[ ! -f "${LOCAL_CONFIG}" ]]; then
  echo "ERROR: File '$(readlink -f "${LOCAL_CONFIG}")' does not exists"
  echo "Create one to configure the location of the matrix token. Example:"
  echo '{"matrix-token": "SUPER_SECRET_TOKEN"}'
fi

CI_ADMIN_ROOT="${SCRIPT_FOLDER}/.."

MATRIX_ENV=${MATRIX_ENV:-""}

MATRIX_ACCESS_TOKEN="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "matrix-token")"

TOKEN_HEADER="Authorization: Bearer ${MATRIX_ACCESS_TOKEN}"

MATRIX_URL="${MATRIX_URL:-"https://matrix${MATRIX_ENV}.eclipse.org"}"
MATRIX_DOMAIN=${MATRIX_URL##*://}

help() {
  printf "Available commands:\n"
  printf "Command\t\tDescription\n\n"
  printf "test_connexion\t\tTest Admin API access.\n"
  printf "test_login\t\tTest Admin API login.\n"
  printf "create_user\t\tCreate matrix bot user.\n"
  printf "get_access_token\t\tGet Access matrix token.\n"
  printf "join_room\t\tJoin a specific room for a user.\n"
  printf "leave_room\t\tLeave room for a user.\n"
  printf "get_room_id\t\Get room id from alias.\n"
  exit 0
}

_check_parameter() {
  local param_name="${1:-}"
  local param="${2:-}"
  # check that parameter is not empty
  if [[ -z "${param}" ]]; then
    printf "ERROR: a %s must be given.\n" "${param_name}" > /dev/tty
    exit 1
  fi
}

test_connexion() {
  local response http_code content
  response=$(curl -sSL -w "\n%{http_code}" \
    --header "${TOKEN_HEADER}" \
    --request GET "${MATRIX_URL}/_synapse/admin/v1/server_version")
  http_code=$(echo "${response}" | tail -n 1)
  content=$(echo "${response}" | head -n -1)

  if [[ "${http_code}" -ne 200 ]]; then
    echo "Synapse Admin API not accessible! Please open a tunnel to the Admin API. HTTP code: ${http_code}, content: ${content}" > /dev/tty
    exit 1
  fi
}

test_login() {
  local response http_code content
  response=$(curl -sSL -w "\n%{http_code}" \
    --header "${TOKEN_HEADER}" \
    --request GET "${MATRIX_URL}/_matrix/client/r0/account/whoami")
  http_code=$(echo "${response}" | tail -n 1)
  content=$(echo "${response}" | head -n -1)

  if [[ "${http_code}" -ne 200 ]]; then
    echo "Synapse Admin API not accessible! Login failed: Invalid access token. HTTP code: ${http_code}, content: ${content}" > /dev/tty
    exit 1
  fi

}

_create_user_api() {
  local username="${1:-}"
  local pw="${2:-}"
  local email="${3:-}" 
  local displayName="${4:-}" 

  curl -sSL \
    --header "${TOKEN_HEADER}" \
    --request PUT "${MATRIX_URL}/_synapse/admin/v2/users/@${username}:${MATRIX_DOMAIN}" \
    -d "{\"displayname\": \"${displayName}\", \"password\": \"${pw}\", \"threepids\":[{\"medium\":\"email\",\"address\":\"${email}\"}]}" 
}

create_user() {
  local project_name="${1:-}"
  local username="${2:-}"
  local pw="${3:-}"
  local email="${4:-}"

  local response http_code content

  _check_parameter "project name" "${project_name}"
  _check_parameter "username" "${username}"
  _check_parameter "password" "${pw}"
  
  local email="${username}@eclipse.org"
  local short_name="${project_name##*.}"
  local displayName="Eclipse ${short_name} bot user"

  response=$(curl -sSL --header "${TOKEN_HEADER}" -w "\n%{http_code}" \
    "${MATRIX_URL}/_synapse/admin/v2/users/@${username}:${MATRIX_DOMAIN}")

  http_code=$(echo "${response}" | tail -n 1)
  content=$(echo "${response}" | head -n -1)

  if [[ "${http_code}" -eq 200 ]]; then
      echo "Bot already exist" > /dev/tty
  elif [[ "${http_code}" -eq 404 ]]; then
    error_code=$(echo "${content}"| jq -e '.errcode')
    if [[ "${error_code}" =~ "M_NOT_FOUND" ]]; then
      echo "Creating user ${username}..." > /dev/tty
      _create_user_api "${username}" "${pw}" "${email}" "${displayName}" | jq .
    else
      echo "Request create failed. HTTP code: ${http_code}, content: ${content}" > /dev/tty
      exit 1
    fi
  else
    echo "Request create failed. HTTP code: ${http_code}, content: ${content}" > /dev/tty
    exit 1  
  fi

}

get_access_token() {
  local username="${1:-}"
  local pw="${2:-}"

  local response http_code content

  _check_parameter "username" "${username}"
  _check_parameter "password" "${pw}"
  
  response=$(curl -sSL --header "${TOKEN_HEADER}" -w "\n%{http_code}" \
    "${MATRIX_URL}/_matrix/client/r0/login" \
    -d '{"type":"m.login.password", "user":"'"${username}"'", "password":"'"${pw}"'"}'
    )

  http_code=$(echo "${response}" | tail -n 1)
  content=$(echo "${response}" | head -n -1)

  if [[ "${http_code}" -eq 200 ]]; then
    echo "${content}"| jq -r '.access_token'    
  else
    echo "Request create bot failed. HTTP code: ${http_code}, content: ${content}" > /dev/tty
    exit 1  
  fi
}

join_room() {
  local token="${1:-}"
  local room_alias="${2:-}"
  
  local response http_code content

  # URL encode # and :"
  room_alias="${room_alias//#/%23}"
  room_alias="${room_alias//:/%3A}"

  response=$(curl -sSL -w "\n%{http_code}" \
    --header "Authorization: Bearer ${token}" \
    --request POST "${MATRIX_URL}/_matrix/client/r0/join/${room_alias}")
  http_code=$(echo "${response}" | tail -n 1)
  content=$(echo "${response}" | head -n -1)

  if [[ "${http_code}" -eq 200 ]]; then
     echo "Join room ${room_alias} OK!" > /dev/tty
  else
    echo "Error joining room ${room_alias}. HTTP code: ${http_code}, content: ${content}" > /dev/tty
    exit 1
  fi
}


leave_room(){
  local token="${1:-}"
  local room_id="${2:-}"

  local response http_code content

  response=$(curl -sSL -w "\n%{http_code}" \
    --header "Authorization: Bearer ${token}" \
    --request POST "${MATRIX_URL}/_matrix/client/r0/rooms/${room_id}/leave")
  http_code=$(echo "${response}" | tail -n 1)
  content=$(echo "${response}" | head -n -1)

  if [[ "${http_code}" -eq 200 ]]; then
     echo "Leave room ${room_id} OK!" > /dev/tty
  else
    echo "Error leaving room ${room_id}. HTTP code: ${http_code}, content: ${content}" > /dev/tty
    exit 1
  fi
}


get_room_id() {

  local token="${1:-}"
  local room_alias="${2:-}"

  local response http_code content

  room_alias="${room_alias//#/%23}"
  room_alias="${room_alias//:/%3A}"

  response=$(curl -sSL -w "\n%{http_code}" \
    --header "Authorization: Bearer ${token}" \
    --request GET "${MATRIX_URL}/_matrix/client/r0/directory/room/${room_alias}")
  http_code=$(echo "${response}" | tail -n 1)
  content=$(echo "${response}" | head -n -1)

  if [[ "${http_code}" -eq 200 ]]; then
    echo "$content" | jq -r '.room_id'
  else
    echo "Error get room id for alias ${room_alias}. HTTP code: ${http_code}, content: ${content}" > /dev/tty
    exit 1  
  fi
}

"$@"

# show help menu, if no first parameter is given
if [[ -z "${1:-}" ]]; then
  help
fi