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

create_central_credentials() {
  printf "\n\nCreating central sonatype credentials...\n"
  "${CI_ADMIN_ROOT}/pass/add_creds.sh" "central" "${PROJECT_NAME}" || true

  local central_username
  local central_password
  central_username="$(passw "cbi" "bots/${PROJECT_NAME}/central.sonatype.org/username")"
  central_password="$(passw "cbi" "bots/${PROJECT_NAME}/central.sonatype.org/password")"
  central_email="$(passw "cbi" "bots/${PROJECT_NAME}/central.sonatype.org/email")"

  cat <<EOF

  # Create Central Sonatype Account

  * Sign-up at Central (use credentials from pass)
    Username:   ${central_username}
    Email:      ${central_email}
    Password:   ${central_password}

    => Sign up here: https://central.sonatype.com/api/auth/login

  * Signup with the new account
  * Validate account email

EOF

  _open_url "https://central.sonatype.com/api/auth/login"  
  read -rsp $'\nOnce you are done, Press any key to continue...\n' -n1
  
  cat <<EOF

  # Request namespace to sonatype support via email

  * Create an email to central-support@sonatype.com
  
  * Subject: Namespace creation for ${DISPLAY_NAME} Project

  * Body: 
    Please create a new namespace at central.sonatype.org for the ${DISPLAY_NAME} project.
    Group ID: org.eclipse.${SHORT_NAME}
    Project URL: https://projects.eclipse.org/projects/${PROJECT_NAME}
    Usernames: ${central_username} (registered at central.sonatype.com)
    SCM URL: https://github.com/eclipse-${SHORT_NAME}

  Issue comment template for HelpDesk issue after the sonatype support has been reached:
  ----------------------------------------------------------------------------------------------------------

  The process for allowing deployments to central sonatype has been started. We are currently waiting sonatype support to be done.
EOF
  
  read -rsp $'\nOnce you are done, Press any key to continue...\n' -n1

}

register_user_token() {

  printf "\n\nRegister User Token...\n"
  python "${SCRIPT_FOLDER}/playwright/central_create_token.py" "${PROJECT_NAME}"

  read -rsp $'\nOnce you are done, Press any key to continue...\n' -n1
   cat <<EOF

  # Add token to Repository Organization (if project doesn't use Jenkins)

  secrets+: [
    orgs.newOrgSecret('CENTRAL_SONATYPE_TOKEN_PASSWORD') {
      value: "pass:bots/${PROJECT_NAME}/central.sonatype.org/token-password",
    },
    orgs.newOrgSecret('CENTRAL_SONATYPE_TOKEN_USERNAME') {
      value: "pass:bots/${PROJECT_NAME}/central.sonatype.org/token-username",
    },
  ],

EOF
}

create_gpg_credentials() {
  printf "\n\nCreating GPG credentials...\n"
  if _check_pw_does_not_exist "${PROJECT_NAME}" "gpg"; then
    "${CI_ADMIN_ROOT}/pass/add_creds_gpg.sh" "${PROJECT_NAME}" "${DISPLAY_NAME} Project"
  fi

  cat <<EOF

  # Add GPG to Repository Organization (if project doesn't use Jenkins)

  secrets+: [
    orgs.newOrgSecret('GPG_KEY_ID') {
      value: "pass:bots/${PROJECT_NAME}/gpg/key_id",
    },
    orgs.newOrgSecret('GPG_PASSPHRASE') {
      value: "pass:bots/${PROJECT_NAME}/gpg/passphrase",
    },
    orgs.newOrgSecret('GPG_PRIVATE_KEY') {
      value: "pass:bots/${PROJECT_NAME}/gpg/secret-subkeys.asc",
    },
  ],

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
    * Central Sonatype
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

otterdog_org_secrets() {
  echo "Add the following organization secrets at org level to the repository: git clone git@github.com/eclipse-${SHORT_NAME}/.eclipsefdn"
  cat <<EOF
  secrets+: [
    orgs.newOrgSecret('GPG_KEY_ID') {
      value: "pass:bots/${PROJECT_NAME}/gpg/key_id",
    },
    orgs.newOrgSecret('GPG_PASSPHRASE') {
      value: "pass:bots/${PROJECT_NAME}/gpg/passphrase",
    },
    orgs.newOrgSecret('GPG_PRIVATE_KEY') {
      value: "pass:bots/${PROJECT_NAME}/gpg/secret-subkeys.asc",
    },
    orgs.newOrgSecret('CENTRAL_SONATYPE_TOKEN_PASSWORD') {
      value: "pass:bots/${PROJECT_NAME}/central.sonatype.org/token-password",
    },
    orgs.newOrgSecret('CENTRAL_SONATYPE_TOKEN_USERNAME') {
      value: "pass:bots/${PROJECT_NAME}/central.sonatype.org/token-username",
    },
  ],
EOF
}


central_comment_template() {
  cat << EOF

  Issue comment template for HelpDesk issue once the Sonatype support is resolved (usually takes a few hours):
  --------------------------------------------------------------------------------------------------------

  The default Maven settings contain a server definition named 'central' to let you upload things to Sonatype's server.
  This server id should be used in a distributionManagement repository somewhere specifying the URL.
  See https://central.sonatype.org/publish/publish-portal-maven/#usage for details.
  The GPG passphrase is also configured (encrypted) in the settings (as described at
  https://maven.apache.org/plugins/maven-gpg-plugin/usage.html#Configure_passphrase_in_settings.xml). It's recommended to use the maven-gpg-plugin.


  Issue comment for project that does not use jenkins: 
  ----------------------------------------------------

  The following organization secrets have been added:
  * GPG_KEY_ID
  * GPG_PASSPHRASE
  * GPG_PRIVATE_KEY
  * CENTRAL_SONATYPE_TOKEN_PASSWORD
  * CENTRAL_SONATYPE_TOKEN_USERNAME
  See https://central.sonatype.org/publish/publish-portal-maven/ on how to publish artifacts to maven central via Sonatype.

EOF
}

namespaces_snapshot() {
  printf "\n\nSet snapshot feature to all namespaces...\n"
  python "${SCRIPT_FOLDER}/playwright/central_namespace_snapshot.py" "${PROJECT_NAME}"
}

# Main
_question_action "create central account" create_central_credentials

_question_action "register User Token in secrets manager (not necessary for jenkins integration)" register_user_token

_question_action "create gpg credentials" create_gpg_credentials

_question_action "create Jenkins credentials" create_jenkins_credentials

_question_action "regenerate Maven settings for Jenkins" regen_maven_settings

_question_action "add otterdog secrets" otterdog_org_secrets

_question_action "set snapshot on namespaces" namespaces_snapshot

_question_action "comment on issue with template" central_comment_template

read -rsp $'\nOnce you are done, Press any key to continue...\n' -n1

printf "\nDone.\n"