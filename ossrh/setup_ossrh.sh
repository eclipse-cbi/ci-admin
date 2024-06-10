#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2022 Eclipse Foundation and others.
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
source "${SCRIPT_FOLDER}/../pass/pass_wrapper.sh"
#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../utils/common.sh"

JIRO_ROOT_FOLDER="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "jiro-root-dir")"

PROJECT_NAME="${1:-}"
DISPLAY_NAME="${2:-}"
SHORT_NAME="${PROJECT_NAME##*.}"

cleanup() {
  rm -rf "${PROJECT_NAME}"
}
trap cleanup EXIT

# check that project name is not empty
if [[ -z "${PROJECT_NAME}" ]]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

# check that display name is not empty
if [ -z "${DISPLAY_NAME}" ]; then
  echo "INFO: No display name was given. Trying to get display name from projects API..."
  DISPLAY_NAME="$(curl -sSL "https://projects.eclipse.org/api/projects/${PROJECT_NAME}.json" | jq -r .[].name)"
  if [ -z "${DISPLAY_NAME}" ]; then
    printf "ERROR: found no display name for '${PROJECT_NAME}' in projects API. Please specify the display name as parameter.\n"
    exit 1
  else
    echo "INFO: Found display name '${DISPLAY_NAME}' for '${PROJECT_NAME}'"
    if [[ "${DISPLAY_NAME}" =~ .*[p|P]roject ]]; then
      echo "Found '[p/P]roject' post fix. Eliminating duplicate."
      DISPLAY_NAME="$(echo ${DISPLAY_NAME} | sed 's/ [p|P]roject//')"
      echo "Fixed display name is '${DISPLAY_NAME}'."
    fi
    read -rsp $'If you confirm that the display name is correct, press any key to continue or CTRL+C to exit the script...\n' -n1
  fi
fi

create_ossrh_credentials() {
  printf "\n\nCreating OSSRH credentials...\n"
  "${CI_ADMIN_ROOT}/pass/add_creds.sh" "ossrh" "${PROJECT_NAME}" || true

  local ossrh_username
  local ossrh_password
  ossrh_username="$(passw "cbi" "bots/${PROJECT_NAME}/oss.sonatype.org/username")"
  ossrh_password="$(passw "cbi" "bots/${PROJECT_NAME}/oss.sonatype.org/password")"
  ossrh_email="$(passw "cbi" "bots/${PROJECT_NAME}/oss.sonatype.org/email")"

  cat <<EOF

  # Create OSSRH Account

  * Sign-up at OSSRH (use credentials from pass)
    Username:   ${ossrh_username}
    Email:      ${ossrh_email}
    Password:   ${ossrh_password}

    => Sign up here: https://central.sonatype.com/api/auth/login

  * Signup with new OSSRH account
  * Validate account email

EOF

  _open_url "https://central.sonatype.com/api/auth/login"  
  read -rsp $'\nOnce you are done, Press any key to continue...\n' -n1
  
  cat <<EOF

  # Request OSSRH Account to sonatype support via email

  * Create an email to central-support@sonatype.com
  
  * Subject: OSSRH Account creation for ${DISPLAY_NAME} Project

  * Body: 
    Please create a new OSSRH Account at oss.sonatype.org for the ${DISPLAY_NAME} project.
    Group ID: org.eclipse.${SHORT_NAME}
    Project URL: https://projects.eclipse.org/projects/${PROJECT_NAME}
    Usernames: ${ossrh_username} (registered at central.sonatype.com)
    SCM URL: https://github.com/eclipse-${SHORT_NAME}

  * NOTE: Adjust SCM URL if needed
  * IMPORTANT: if it’s an ee4j project, mention that the permissions need to be set for https://jakarta.oss.sonatype.org not https://oss.sonatype.org

  Issue comment template for HelpDesk issue after the OSSRH support has been reached:
  ----------------------------------------------------------------------------------------------------------

  The process for allowing deployments to OSSRH has been started. We are currently waiting sonatype support to be done.
EOF
  
  read -rsp $'\nOnce you are done, Press any key to continue...\n' -n1

}

register_user_token() {

  printf "\n\nRegister User Token...\n"

  local nexusProUrl
  local ossrh_username
  local ossrh_password
  nexusProUrl="https://oss.sonatype.org"
  ossrh_username="$(passw "cbi" "bots/${PROJECT_NAME}/oss.sonatype.org/username")"
  ossrh_password="$(passw "cbi" "bots/${PROJECT_NAME}/oss.sonatype.org/password")"

  local ossrh_token
  ossrh_token="$("${JIRO_ROOT_FOLDER}/build/nexus-pro-token.sh" get_or_create "${nexusProUrl}" "${ossrh_username}" "${ossrh_password}")"
  ossrh_token_username="$(jq -r '.nameCode' <<< "${ossrh_token}")"
  ossrh_token_password="$(jq -r '.passCode' <<< "${ossrh_token}")"

  echo "${ossrh_token_username}" | passw cbi insert -m "bots/${PROJECT_NAME}/oss.sonatype.org/gh-token-username"
  echo "${ossrh_token_password}" | passw cbi insert -m "bots/${PROJECT_NAME}/oss.sonatype.org/gh-token-password"

  cat <<EOF

  # Check User Token 

  * Login with bot account to https://oss.sonatype.org
    Username:   ${ossrh_username}
    Password:   ${ossrh_password}
    Username Token:   ${ossrh_token_username}
    Password Token:   ${ossrh_token_password}

  * Go to user profil, and select in the dropdown 'User Token' panel: https://oss.sonatype.org/#profile;User%20Token
  * Click 'Access User Token'

  # Add OSSRH Token to Repository Organization (if project doesn't use Jenkins)

  * ORG_OSSRH_USERNAME: ${ossrh_token_username}
  * ORG_OSSRH_PASSWORD: ${ossrh_token_password}
  
EOF
  _open_url "https://oss.sonatype.org"  
  read -rsp $'\nOnce you are done, Press any key to continue...\n' -n1
}

create_gpg_credentials() {
  printf "\n\nCreating GPG credentials...\n"
  if _check_pw_does_not_exist "${PROJECT_NAME}" "gpg"; then
    "${CI_ADMIN_ROOT}/pass/add_creds_gpg.sh" "${PROJECT_NAME}" "${DISPLAY_NAME} Project"
  fi

  gpg_passphrase="$(passw "cbi" "bots/${PROJECT_NAME}/gpg/passphrase")"
  gpg_secret="$(passw "cbi" "bots/${PROJECT_NAME}/gpg/secret-subkeys.asc")"
  cat <<EOF

  # Add GPG to Repository Organization (if project doesn't use Jenkins)

  * ORG_GPG_PASSPHRASE: ${gpg_passphrase}
  * ORG_GPG_PRIVATE_KEY: 
  ${gpg_secret}

  Add those credentials to the repository organization secrets.
 
EOF
}

create_jenkins_credentials() {

  printf "\n\nCreating Jenkins credentials...\n"
  "${JIRO_ROOT_FOLDER}/jenkins-create-credentials.sh" "${PROJECT_NAME}"

  mkdir -p "${PROJECT_NAME}"
  passw "cbi" "bots/${PROJECT_NAME}/gpg/secret-subkeys.asc" > "${PROJECT_NAME}/secret-subkeys.asc"

  cat << EOF

  # Add secret-subkeys.asc to Jenkins credentials

    * Click on name 'secret-subkeys.asc'
    * Update
    * Select 'Replace' checkbox
    * Browse
    * Open folder '${PWD}/${PROJECT_NAME}'
    * Select file 'secret-subkeys.asc'

EOF

  _open_url "https://ci.eclipse.org/${SHORT_NAME}/credentials"

  echo "* Push changes to pass"
  read -rsp $'\nPress any key to continue...\n' -n1

  cat << EOF

  # Reply to ticket:
  
  The following credentials have been added to the ${DISPLAY_NAME} CI instance:
    * OSSRH
    * GPG

EOF
  read -rsp $'\nPress any key to continue...\n' -n1
}

regen_maven_settings() {
  echo
  echo "Regenerating Maven settings file for Jenkins instance..."
  pushd "${JIRO_ROOT_FOLDER}/incubation" > /dev/null
  ./regen_maven_settings.sh "../instances/${PROJECT_NAME}"
  popd > /dev/null
}

ossrh_comment_template() {
  cat << EOF

  Issue comment template for HelpDesk issue once the OSSRH support is resolved (usually takes a few hours):
  --------------------------------------------------------------------------------------------------------

  The default Maven settings contain a server definition named 'ossrh' to let you upload things to Sonatype's server.
  This server id should be used in a distributionManagement repository somewhere specifying the URL.
  See http://central.sonatype.org/pages/ossrh-guide.html#releasing-to-central and http://central.sonatype.org/pages/ossrh-guide.html#ossrh-usage-notes for details.
  The GPG passphrase is also configured (encrypted) in the settings (as described at
  https://maven.apache.org/plugins/maven-gpg-plugin/usage.html#Configure_passphrase_in_settings.xml). It's recommended to use the maven-gpg-plugin.
  See also https://github.com/eclipse-cbi/jiro/wiki/Jenkins#how-can-artifacts-be-deployed-to-ossrh--maven-central


  Issue comment for project that does not use jenkins: 
  ----------------------------------------------------

  The following organization secrets have been added:
  * ORG_GPG_PASSPHRASE
  * ORG_GPG_PRIVATE_KEY
  * ORG_OSSRH_PASSWORD
  * ORG_OSSRH_USERNAME
  See https://central.sonatype.org/publish/publish-maven/ on how to publish artifacts to maven central via Sonatype.

EOF
}

# Main
_question_action "create ossrh credentials" create_ossrh_credentials

_question_action "register User Token in secrets manager (not necessary for jenkins integration)" register_user_token

_question_action "create gpg credentials" create_gpg_credentials

_question_action "create Jenkins credentials" create_jenkins_credentials

_question_action "regenerate Maven settings for Jenkins" regen_maven_settings

ossrh_comment_template

read -rsp $'\nOnce you are done, Press any key to continue...\n' -n1

printf "\nDone.\n"