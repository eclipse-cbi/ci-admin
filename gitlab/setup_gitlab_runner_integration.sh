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
SCRIPT_FOLDER="$(dirname "$(readlink -f "${0}")")"
CI_ADMIN_ROOT="${SCRIPT_FOLDER}/.."

#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../utils/common.sh"

PROJECTS_BOTS_API_ROOT_FOLDER="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "projects-bots-api-root-dir")"

PROJECT_NAME="${1:-}"
SHORT_NAME="${PROJECT_NAME##*.}"

# check that project name is not empty
if [[ -z "${PROJECT_NAME}" ]]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

update_projects_bot_api() {
  # check if project bot api entry already exists:
  if ! curl -sSL "https://api.eclipse.org/bots" | jq -e '.[] | select(.projectId=="'${PROJECT_NAME}'") | has("gitlab.eclipse.org")' > /dev/null ; then
    printf "\n# Updating projects-bots-api...\n"
    "${PROJECTS_BOTS_API_ROOT_FOLDER}"/regen_db.sh
  else
    printf "\n# projects-bots-api entry for gitlab.eclipse.org already exists. Skipping...\n"
  fi
}

add_bot_to_group() {
  printf "\n# Adding bot to GitLab group...\n"
  # TODO: read botname from pass?
  bot_name="${SHORT_NAME}-bot"
  group_name="${SHORT_NAME}"
  access_level=50 # 50 = Owner
  "${SCRIPT_FOLDER}/gitlab_admin.sh" "add_user_to_group" "${group_name}" "${bot_name}" "${access_level}"
}

#### MAIN

echo "# Creating a GitLab bot user..."
"${SCRIPT_FOLDER}/create_gitlab_bot_user.sh" "${PROJECT_NAME}"

add_bot_to_group

update_projects_bot_api

printf "\n\n# TODO: Commit changes to pass...\n"
read -rsp $'Once you are done, press any key to continue...\n' -n1
