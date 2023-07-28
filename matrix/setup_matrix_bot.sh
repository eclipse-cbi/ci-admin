#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2023 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html,
# or the MIT License which is available at https://opensource.org/licenses/MIT.
# SPDX-License-Identifier: EPL-2.0 OR MIT
#*******************************************************************************

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'
SCRIPT_FOLDER="$(dirname "$(readlink -f "${0}")")"
CI_ADMIN_ROOT="${SCRIPT_FOLDER}/.."

#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../utils/common.sh"
#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../pass/pass_wrapper.sh"

JIRO_ROOT_FOLDER="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "jiro-root-dir")"

PROJECT_NAME="${1:-}"
SHORT_NAME="${PROJECT_NAME##*.}"

export MATRIX_ENV=""
[[ -n "$MATRIX_ENV" ]] && MATRIX_ENV="-${MATRIX_ENV}"

MATRIX_URL="${MATRIX_URL:-"https://matrix${MATRIX_ENV}.eclipse.org"}"
MATRIX_DOMAIN=${MATRIX_URL##*://}

MATRIX_PASS_DOMAIN="matrix.eclipse.org"
PW_STORE_PATH="bots/${PROJECT_NAME}/${MATRIX_PASS_DOMAIN}"

# check that project name is not empty
if [[ -z "${PROJECT_NAME}" ]]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

create_matrix_credentials() {
  echo "# Creating Matrix bot user credentials..."
  "${CI_ADMIN_ROOT}/pass/add_creds.sh" "matrix" "${PROJECT_NAME}" || true
}

create_matrix_bot_account() {
  local username pw email
  username=$(passw cbi "${PW_STORE_PATH}/username")
  pw=$(passw cbi "${PW_STORE_PATH}/password")
  email=$(passw cbi "${PW_STORE_PATH}/email")

  "${SCRIPT_FOLDER}/matrix_admin.sh" "create_user" "${PROJECT_NAME}" "${username}" "${pw}" "${email}"
}

validate_consent(){
  local username form_secret hash url
  username=$(passw cbi "${PW_STORE_PATH}/username")
  
  matrix_secret_env=${MATRIX_ENV#-}
  matrix_secret_env=${matrix_secret_env:-"prod"}

  form_secret=$(passw it "/IT/services/chat-service/synapse/${matrix_secret_env}/form_secret")
  hash=$(echo -n "${username}" | openssl sha256 -hmac "${form_secret}" | cut -d "=" -f 2 | tr -d '[:space:]')
  url="https://${MATRIX_DOMAIN}/_matrix/consent?u=${username}&h=${hash}"

  echo "Open this link to consent policy: ${url}"
  _open_url "${url}"
}

get_token() {
  local username pw token
  username=$(passw cbi "${PW_STORE_PATH}/username")
  pw=$(passw cbi "${PW_STORE_PATH}/password")
  token=$("${SCRIPT_FOLDER}/matrix_admin.sh" "get_access_token" "${username}" "${pw}")
  echo "${token}" | passw cbi insert --echo "${PW_STORE_PATH}/token"
}

join_room() {
  local botToken  
  botToken=$(passw cbi "${PW_STORE_PATH}/token")

  read -rp "Room Alias in which the bot interact (i.e: #${SHORT_NAME}-releng:${MATRIX_DOMAIN})" room
  "${SCRIPT_FOLDER}/matrix_admin.sh" "join_room" "${botToken}" "${room}"
}

leave_eclipse_space() {
  local botToken  
  botToken=$(passw cbi "${PW_STORE_PATH}/token")

  local room_aliases=("#eclipse-projects:${MATRIX_DOMAIN}" "#eclipsefdn:${MATRIX_DOMAIN}")

  for room_alias in "${room_aliases[@]}"
  do
    room_id=$("${SCRIPT_FOLDER}/matrix_admin.sh" "get_room_id" "${botToken}" "${room_alias}")
    "${SCRIPT_FOLDER}/matrix_admin.sh" "leave_room" "${botToken}" "${room_id}"
  done
}

add_jenkins_credentials() {
  printf "\n# Adding matrix bot credentials to Jenkins instance...\n"
  if [[ -d "${JIRO_ROOT_FOLDER}/instances/${PROJECT_NAME}" ]]; then
    echo "Found Jenkins instance for ${PROJECT_NAME}..."
    "${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "auto" "${PROJECT_NAME}"
  else
    echo "No Jenkins instance for ${PROJECT_NAME}..."
  fi 
}

#### MAIN

echo "##############################################################################"
echo "Prerequisite : "
echo "* Open tunnel to matrix synapse admin API "
echo "* Activate matrix registration password in homeserver configuration: password_config: { enabled: true }"
echo "##############################################################################"

read -rsp $'Press any key to continue...\n' -n1

echo "Working on matrix instance : ${MATRIX_URL}"

"${SCRIPT_FOLDER}/matrix_admin.sh" "test_connexion"
"${SCRIPT_FOLDER}/matrix_admin.sh" "test_login"

echo "##############################################################################"
_question_action "Create Credential for Matrix bot user" create_matrix_credentials

echo "##############################################################################"
_question_action "Create Matrix bot user" create_matrix_bot_account

echo "##############################################################################"
_question_action "Validate Matrix bot user consent" validate_consent

echo "##############################################################################"
_question_action "Get Matrix bot user token" get_token

echo "##############################################################################"
_question_action "Join bot to matrix room" join_room

echo "##############################################################################"
_question_action "Leave #eclipse and #eclipsefdn-project default spaces" leave_eclipse_space

echo "##############################################################################"
_question_action "Add Matrix bot token to Jenkins credentials" add_jenkins_credentials

echo "##############################################################################"
echo "Post actions : "
echo "* Push pass credentials"
echo "* Deactivate matrix registration password in homeserver configuration: password_config: { enabled: false }"
echo "##############################################################################"

read -rsp $'Once you are done, press any key to continue...\n' -n1

