#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2024 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html,
# or the MIT License which is available at https://opensource.org/licenses/MIT.
# SPDX-License-Identifier: EPL-2.0 OR MIT
#*******************************************************************************

# Provision a new gitlab-runner instance in GRAC

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
CI_ADMIN_ROOT="${SCRIPT_FOLDER}/.."

PROJECT_NAME="${1:-}"
DISPLAY_NAME="${2:-}"

usage() {
  printf "Usage: %s project_name display_name\n" "${SCRIPT_NAME}"
  printf "\t%-16s project name (e.g. technology.cbi for CBI project).\n" "project_name"
  printf "\t%-16s display name (e.g. 'Eclipse CBI' for CBI project).\n" "display_name"
}

# check that project name is not empty
if [ -z "${PROJECT_NAME}" ]; then
  printf "ERROR: a project name must be given.\n"
  usage
  exit 1
fi

if [ -z "${DISPLAY_NAME}" ]; then
  echo "INFO: No display name was given. Trying to get display name from projects API..."
  DISPLAY_NAME="$(curl -sSL "https://projects.eclipse.org/api/projects/${PROJECT_NAME}.json" | jq -r .[].name)"
  if [ -z "${DISPLAY_NAME}" ]; then
    printf "ERROR: found no display name for '${PROJECT_NAME}' in projects API. Please specify the display name as parameter.\n"
    exit 1
  else
    echo "INFO: Found display name '${DISPLAY_NAME}' for '${PROJECT_NAME}'"
    read -rsp $'If you confirm that the display name is correct, press any key to continue or CTRL+C to exit the script...\n' -n1
  fi
fi

GRAC_ROOT_FOLDER="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "grac-root-dir")"

setup_projects_storage() {
  printf "\n\n### Setting up projects storage credentials...\n"
  pushd "${CI_ADMIN_ROOT}/projects-storage" > /dev/null
  ./setup_projects_storage.sh "${PROJECT_NAME}"
  popd > /dev/null
  printf "\n"
}

setup_gitlab_bot() {
  printf "\n\n### Setting up Gitlab bot...\n"
  pushd "${CI_ADMIN_ROOT}/gitlab" > /dev/null
  ./setup_gitlab_runner_integration.sh "${PROJECT_NAME}"
  popd > /dev/null
  printf "\n"
}

setup_ossrh() {
  pushd "${CI_ADMIN_ROOT}/ossrh" > /dev/null
  ./setup_ossrh.sh "${PROJECT_NAME}" "${DISPLAY_NAME}"
  popd > /dev/null
  printf "\n"
}

setup_grac() {
  pushd "${GRAC_ROOT_FOLDER}" > /dev/null
  "./grac.sh" create "${PROJECT_NAME}"
  "./grac.sh" init "${PROJECT_NAME}"
  popd > /dev/null
}

question() {
  local message="${1:-}"
  local action="${2:-}"
  read -rp "Do you want to ${message}? (Y)es, (N)o, E(x)it: " yn
  case $yn in
    [Yy]* ) ${action};;
    [Nn]* ) return ;;
    [Xx]* ) exit 0;;
        * ) echo "Please answer (Y)es, (N)o, E(x)it"; question "${message}" "${action}";
  esac
}

issue_template() {
  cat <<EOF

Post the following on the corresponding HelpDesk issue:
-------------------------------------------------------

GitLab Runner is available for the project ${PROJECT_NAME}.

NOTE: You can find all information on Grac here: https://gitlab.eclipse.org/eclipsefdn/it/releng/gitlab-runner-service/gitlab-runner-service-documentation

Please let us know if you need any additional information.

-----------------------------------------------------

EOF
read -rsp $'Once you are done, press any key to continue...\n' -n1
}

## MAIN ##

echo "Connected to cluster?"
read -rp "Press enter to continue or CTRL-C to stop the script"

question "setup GitLab bot" "setup_gitlab_bot"

question "setup Projects storage credentials" "setup_projects_storage"
question "setup OSSRH credentials" "setup_ossrh"

question "setup new Grac instance" "setup_grac"

echo "WARN: secretsmanager configuration must be done manually"

issue_template

#TODO: commit changes to Grac repo
pushd "${GRAC_ROOT_FOLDER}" > /dev/null
git add "${GRAC_ROOT_FOLDER}/instances/${PROJECT_NAME}"
#git commit -m "feat: Provisioning Runner for project ${PROJECT_NAME}"
popd > /dev/null
