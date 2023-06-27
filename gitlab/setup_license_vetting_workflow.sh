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
LOCAL_CONFIG="${HOME}/.cbi/config"

if [[ ! -f "${LOCAL_CONFIG}" ]]; then
  echo "ERROR: File '$(readlink -f "${LOCAL_CONFIG}")' does not exists"
  echo "Create one to configure the location of the projects-bots-api root dir. Example:"
  echo '{"projects-bots-api-root-dir": "/path/to/projects-bots-api/rootdir"}'
  exit 1
fi

PROJECTS_BOTS_API_ROOT_FOLDER="$(jq -r '."projects-bots-api-root-dir"' < "${LOCAL_CONFIG}")"

if [[ -z "${PROJECTS_BOTS_API_ROOT_FOLDER}" ]] || [[ "${PROJECTS_BOTS_API_ROOT_FOLDER}" == "null" ]]; then
  printf "ERROR: 'projects-bots-api-root-dir' must be set in %s.\n" "${LOCAL_CONFIG}"
  exit 1
fi

PROJECT_NAME="${1:-}"
SHORT_NAME="${PROJECT_NAME##*.}"

# check that project name is not empty
if [[ -z "${PROJECT_NAME}" ]]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

update_projects_bot_api() {
#TODO: don't update if the bot has been added before
  printf "\n# Update projects-bots-api...\n"

  pushd "${PROJECTS_BOTS_API_ROOT_FOLDER}"
  echo "* Pulling latest version of projects-bots-api..."
  git pull
  echo "* Regenerating projects-bots-api DB..."
  regen_db.sh

  printf "\n\n"
#TODO: Show error if files are equal
  read -rsp $'Once you are done with comparing the diff, press any key to continue...\n' -n1

  echo "* Committing changes to projects-bots-api repo..."
  git add bots.db.json
  git commit -m "Update bots.db.json"
  git push
  popd

  echo "* Commit should trigger a build of https://foundation.eclipse.org/ci/webdev/job/projects-bots-api/job/master..."
  echo
  echo "* TODO: Wait for the build to finish..."
  printf "* TODO: Double check that bot account has been added to API (https://api.eclipse.org/bots)...\n"
  read -rsp $'Once you are done, press any key to continue...\n' -n1
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