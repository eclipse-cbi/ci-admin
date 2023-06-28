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

PROJECTS_BOTS_API_ROOT_FOLDER="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "projects-bots-api-root-dir")"

PROJECT_NAME="${1:-}"
SHORT_NAME="${PROJECT_NAME##*.}"

# check that project name is not empty
if [[ -z "${PROJECT_NAME}" ]]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

update_projects_bot_api() {
  printf "\n# Updating projects-bots-api...\n"
  "${PROJECTS_BOTS_API_ROOT_FOLDER}"/regen_db.sh
}

add_secret_to_github_repo() {
  cat <<EOF

TODO:
* add API token to the requested GitHub repositories/organization as repository/organization secret (ID: GITLAB_API_TOKEN) or
* add API token to CI instance


EOF
  read -rsp $'Once you are done, press any key to continue...\n' -n1
}

issue_response_template() {
  printf "\n# Post instructions to GitLab...\n"
  cat <<EOF
Post the following on the corresponding GitLab issue:
-------------------------------------------------------

A GitLab bot user for the ${PROJECT_NAME} project (username: ${SHORT_NAME}-bot) and an API token have been created.

The API token has been added to the following GitHub repositories/organization as repository/organization secrets (ID: GITLAB_API_TOKEN):

<LIST OF REPOS/ORGANIZATION>

EOF
  read -rsp $'Once you are done, press any key to continue...\n' -n1
}

####

echo "# Creating a GitLab bot user..."
"${SCRIPT_FOLDER}/create_gitlab_bot_user.sh" "${PROJECT_NAME}"

update_projects_bot_api

#TODO: automate
add_secret_to_github_repo

issue_response_template

echo
echo "TODO:"
echo "* Push changes to cbi-pass repo"
echo
read -rsp $'Once you are done, press any key to continue...\n' -n1

echo "Done."