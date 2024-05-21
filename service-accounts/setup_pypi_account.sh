#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2024 Eclipse Foundation and others.
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
SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
CI_ADMIN_ROOT="${SCRIPT_FOLDER}/.."

#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../utils/common.sh"

JIRO_ROOT_FOLDER="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "jiro-root-dir")"

PROJECT_NAME="${1:-}"

# check that project name is not empty
if [[ -z "${PROJECT_NAME}" ]]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

SHORT_NAME="${PROJECT_NAME##*.}"

create_pass_credentials() {
  printf "# Creating pass credentials...\n"
  "${CI_ADMIN_ROOT}/pass/add_creds.sh" "user_pw" "${PROJECT_NAME}" "pypi.org" "${SHORT_NAME}-bot@eclipse.org" "eclipse-${SHORT_NAME}-bot"
}

sign_up() {
  printf "\n\n# Sign up at pypi.org...\n"
  #TODO: use playwright
  _open_url "https://pypi.org/account/register"
  printf "\n# TODO: Create pypi.org bot account (semi manually)...\n"
  cat <<EOF
  * Name: ${SHORT_NAME} Bot
  * Email: ${SHORT_NAME}-bot@eclipse.org
  * Username: eclipse-${SHORT_NAME}-bot
  * Password: <from pass>
  * Set up 2FA!
    * Add recovery codes to pass as '2FA-recovery-codes'
    * Use 'Add 2FA with authentication application'
    * Add seed to pass as '2FA-seed'
  * Create access token (Scope: Entire account (all projects))
    * Add to pass as 'api-token'
EOF
  read -rsp $'Once you are done, press any key to continue...\n' -n1
}

add_jenkins_credentials() {
  "${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "pypi" "${PROJECT_NAME}"
}

issue_comment_jenkins() {
  cat <<EOF

Post the following on the corresponding HelpDesk issue:
-------------------------------------------------------
A bot user on pypi.org has been created (ID: 'eclipse-${SHORT_NAME}-bot'). The access token for it has been added to the project's Jenkins instance.
The ID is:
EOF
  read -rsp $'Once you are done, press any key to continue...\n' -n1
}

issue_comment_github() {
  cat <<EOF

Post the following on the corresponding HelpDesk issue:
-------------------------------------------------------
A bot user at pypi.org has been created (ID: 'eclipse-${SHORT_NAME}-bot'). The access token for it has been added to the 'eclipse-${SHORT_NAME}' GitHub org as secrets:
* 'PYPI_TOKEN'

From the pypi.org docs:
>    Set your username to '__token__' \
>    Set your password to the token value, including the 'pypi-' prefix

EOF
  read -rsp $'Once you are done, press any key to continue...\n' -n1
}

add_entry_to_spreadsheet() {
  printf "\nTODO: Add entry to service account spreadsheet.\n"
  read -rsp $'Once you are done, press any key to continue...\n' -n1
}

#### MAIN

create_pass_credentials

sign_up

#check if project has a Jenkins instance
if [[ -d "${JIRO_ROOT_FOLDER}/instances/${PROJECT_NAME}" ]]; then
  echo "Found Jenkins instance for ${PROJECT_NAME}..."
  _question_action "add Jenkins credentials" add_jenkins_credentials
  issue_comment_jenkins
  #TODO: handle GitLab
else
  #TODO: set up GitHub credentials (PYPI_TOKEN as org secret)
  issue_comment_github
fi

add_entry_to_spreadsheet
