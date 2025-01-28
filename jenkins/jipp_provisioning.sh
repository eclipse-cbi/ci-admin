#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2021 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html,
# or the MIT License which is available at https://opensource.org/licenses/MIT.
# SPDX-License-Identifier: EPL-2.0 OR MIT
#*******************************************************************************

# Provision a new Jenkins instance on JIRO

#  - check genie user on projects-storages
#    - check if genie home dir exists
#    - check if download dir exists
#    - check if genie user is part of the project LDAP/Unix group
#  - fix LDAP on projects-storage
#  - create Gerrit credentials and add them to pass (TODO: remove)
#  - create projects-storage credentials and add them to pass
#  - add pub key to genie to .ssh/authorized_keys in home dir on projects-storage
#  - create new JIRO JIPP
#  - ask if GitHub credentials should be set up
#  - ask if OSSRH credentials should be set up
#  - show issue template


# TODO:
# * make scripts robust (work when run multiple times)
# * fix pass path for good

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
CI_ADMIN_ROOT="${SCRIPT_FOLDER}/.."

#TODO: refactor expect scripts?

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

JIRO_ROOT_FOLDER="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "jiro-root-dir")"


setup_projects_storage() {
  printf "\n\n### Setting up projects storage credentials...\n"
  pushd "${CI_ADMIN_ROOT}/projects-storage" > /dev/null
  ./setup_projects_storage.sh "${PROJECT_NAME}"
  popd > /dev/null
  printf "\n"
}

setup_github() {
  printf "\n\n### Setting up GitHub bot credentials...\n"
  pushd "${CI_ADMIN_ROOT}/github" > /dev/null
  ./setup_github_bot.sh "${PROJECT_NAME}"
  popd > /dev/null
  printf "\n"
}

setup_ossrh() {
  pushd "${CI_ADMIN_ROOT}/ossrh" > /dev/null
  ./setup_ossrh.sh "${PROJECT_NAME}" "${DISPLAY_NAME}"
  popd > /dev/null
  printf "\n"
}

setup_jipp() {
  "${JIRO_ROOT_FOLDER}/incubation/create_new_jiro_jipp.sh" "${PROJECT_NAME}" "${DISPLAY_NAME}"
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
  local short_name="${PROJECT_NAME##*.}"
  cat <<EOF

Post the following on the corresponding HelpDesk issue:
-------------------------------------------------------

The ${DISPLAY_NAME} JIPP on Jiro is available here now:

=> https://ci.eclipse.org/${short_name}

PLEASE NOTE:
* Publishing to download.eclipse.org requires access via SCP. We've added the credentials to the JIPP. Please see https://github.com/eclipse-cbi/jiro/wiki/FAQ#how-do-i-deploy-artifacts-to-downloadeclipseorg for more info.

* To simplify setting up jobs on our cluster-based infra, we provide a pod template that can also be used with freestyle jobs. The pod template has the label "centos-7" which can be specified in the job configuration under "Restrict where this project can be run". The image contains more commonly used dependencies than the default “basic” pod template.

* You can find more info about Jenkins here: https://github.com/eclipse-cbi/jiro/wiki

Please let us know if you need any additional plug-ins.

-----------------------------------------------------

EOF
read -rsp $'Once you are done, press any key to continue...\n' -n1
}

## MAIN ##

echo "Connected to cluster?"
read -rp "Press enter to continue or CTRL-C to stop the script"

# ask if projects storage credentials should be created
question "setup Projects storage credentials" "setup_projects_storage"

# ask if the jipp should be created
question "setup new JIPP instance" "setup_jipp"

# ask if GitHub bot credentials should be created
question "setup GitHub bot credentials" "setup_github"

# ask if OSSRH/gpg credentials should be created
question "setup OSSRH credentials" "setup_ossrh"

#TODO: only if github or ossrh setup was executed
# create Jenkins credentials
"${JIRO_ROOT_FOLDER}/jenkins-create-credentials.sh" "${PROJECT_NAME}"
"${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "auto" "${PROJECT_NAME}"

issue_template

#TODO: commit changes to JIRO repo
pushd "${JIRO_ROOT_FOLDER}" > /dev/null
git add "${JIRO_ROOT_FOLDER}/instances/${PROJECT_NAME}"
#git commit -m "Provisioning JIPP for project ${PROJECT_NAME}"
popd > /dev/null

rm -rf "${PROJECT_NAME}"
