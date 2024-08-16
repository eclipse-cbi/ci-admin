#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2021 Eclipse Foundation and others.
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

JIRO_ROOT_FOLDER="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "jiro-root-dir")"
PROJECTS_BOTS_API_ROOT_FOLDER="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "projects-bots-api-root-dir")"

PROJECT_NAME="${1:-}"

# check that project name is not empty
if [[ -z "${PROJECT_NAME}" ]]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

SHORT_NAME="${PROJECT_NAME##*.}"

# TODO:
# * deal with multiple executions due to errors
#     * do not create github credentials if they already exist
# * add confirmations/questions
# * improve instructions

create_github_credentials() {
  echo "# Creating GitHub bot user credentials..."
  "${CI_ADMIN_ROOT}/pass/add_creds.sh" "github" "${PROJECT_NAME}" || true
  "${CI_ADMIN_ROOT}/pass/add_creds.sh" "github_ssh" "${PROJECT_NAME}" || true
}

set_up_github_account() {
  echo "# Setting up GitHub bot account..."
  python "playwright/gh_signup.py" "${PROJECT_NAME}"
}

add_jenkins_credentials() {
#TODO: check that token credentials have been created
  printf "\n# Adding GitHub bot credentials to Jenkins instance...\n"
  "${JIRO_ROOT_FOLDER}/jenkins-create-credentials.sh" "${PROJECT_NAME}"
  "${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "auto" "${PROJECT_NAME}"
}

update_projects_bot_api() {
  # check if project bot api entry already exists:
  if ! curl -sSL "https://api.eclipse.org/bots" | jq -e '.[] | select(.projectId=="'${PROJECT_NAME}'") | has("github.com")'; then
    printf "\n# Updating projects-bots-api...\n"
    "${PROJECTS_BOTS_API_ROOT_FOLDER}"/regen_db.sh
  else
    printf "\n# projects-bots-api entry for github.com already exists. Skipping...\n"
  fi
}

create_org_webhook() {
  echo "# Creating organization webhook..."
  "${SCRIPT_FOLDER}/create_webhook.sh" "org" "${PROJECT_NAME}" "eclipse-${SHORT_NAME}"
}

instructions_template() {
  cat <<EOF

Post the following on the corresponding HelpDesk issue:
-------------------------------------------------------
A GitHub bot (ID: eclipse-${SHORT_NAME}-bot) has been created. Credentials have been added to the ${SHORT_NAME} JIPP.

The recommended way to set up a job that builds pull requests is to use a Multibranch Pipeline job (a Jenkinsfile in your repo is required):
1. New item > Multibranch Pipeline
2. Branch Sources > Add source > GitHub
3. Select credentials "GitHub bot (username/token)"
4. Add the repository URL
5. Configure behaviors
6. Save

By default, all branches and PRs will be scanned and dedicated build jobs will be created automatically (if a Jenkinsfile is found).

EOF
}

#### MAIN

create_github_credentials

set_up_github_account

_question_action "update the projects bot API" update_projects_bot_api

#check if project has a Jenkins instance
if [[ -d "${JIRO_ROOT_FOLDER}/instances/${PROJECT_NAME}" ]]; then
  echo "Found Jenkins instance for ${PROJECT_NAME}..."
  _question_action "add Jenkins credentials" add_jenkins_credentials
  _question_action "create an org webhook" create_org_webhook
  printf "\n# TODO: Set up GitHub config in Jenkins (if applicable)...\n"
  instructions_template
fi

printf "\n\n# TODO: Commit changes to pass...\n"
read -rsp $'Once you are done, press any key to continue...\n' -n1

