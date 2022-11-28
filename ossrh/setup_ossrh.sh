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

JIRO_ROOT_FOLDER="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "jiro-root-dir")"

PROJECT_NAME="${1:-}"
DISPLAY_NAME="${2:-}"
SHORT_NAME="${PROJECT_NAME##*.}"

# check that project name is not empty
if [[ -z "${PROJECT_NAME}" ]]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

# check that display name is not empty
if [[ -z "${DISPLAY_NAME}" ]]; then
  printf "ERROR: a display name (e.g. 'Eclipse CBI Project') must be given.\n"
  exit 1
fi

open_url() {
  local url="${1:-}"
  if which xdg-open > /dev/null; then # most Linux
    xdg-open "${url}"
  elif which open > /dev/null; then # macOS
    open "${url}"
  fi
}

create_ossrh_credentials() {
  printf "\nCreating OSSRH credentials...\n"
  "${CI_ADMIN_ROOT}/pass/add_creds.sh" "ossrh" "${PROJECT_NAME}" || true

  local username
  local pw
  username="$(passw "cbi" "bots/${PROJECT_NAME}/oss.sonatype.org/username")"
  pw="$(passw "cbi" "bots/${PROJECT_NAME}/oss.sonatype.org/password")"
  printf "\n# TODO (manually!):\n"
  echo "* Sign-up at OSSRH (use credentials from pass)"
  echo "  Email:      ${SHORT_NAME}-bot@eclipse.org"
  echo "  Full name:  ${DISPLAY_NAME} Project"
  echo "  Username:   ${username}"
  echo "  Password:   ${pw}"
  echo "  => Sign up here: https://issues.sonatype.org/secure/Signup!default.jspa"
  open_url "https://issues.sonatype.org/secure/Signup!default.jspa"
  printf "\n* Login with new OSSRH account\n"
  read -rsp $'\nOnce you are done, press any key to continue...' -n1
  printf "\n* Create an issue here: https://issues.sonatype.org/secure/CreateIssue.jspa?issuetype=21&pid=10134\n"
  open_url "https://issues.sonatype.org/secure/CreateIssue.jspa?issuetype=21&pid=10134"
  echo "  * Template: https://issues.sonatype.org/browse/OSSRH-21895"
  echo "  * Summary: ${DISPLAY_NAME} Project"
  echo "  * Description: Please create the appropriate configuration for the ${DISPLAY_NAME} project. Thanks"
  echo "  * Group ID: org.eclipse.${SHORT_NAME}"
  echo
  echo "  * IMPORTANT: if it’s an ee4j project, mention that the permissions need to be set for https://jakarta.oss.sonatype.org not https://oss.sonatype.org"
  read -rsp $'\nOnce you are done, press any key to continue...' -n1
  echo
}

create_gpg_credentials() {
  printf "Creating GPG credentials...\n"
#TODO: skip if GPG creds already exist
  "${CI_ADMIN_ROOT}/pass/add_creds_gpg.sh" "${PROJECT_NAME}" "${DISPLAY_NAME} Project"
}

create_jenkins_credentials() {
  printf "\n\nCreating Jenkins credentials...\n"
  "${JIRO_ROOT_FOLDER}/jenkins-create-credentials.sh" "${PROJECT_NAME}"

  #dump secret-subkeys.asc to temp folder
  mkdir -p "${PROJECT_NAME}"
  passw "cbi" "bots/${PROJECT_NAME}/gpg/secret-subkeys.asc" > "${PROJECT_NAME}/secret-subkeys.asc"

  printf "\n# TODO (manually!):\n"
  echo "* Add secret-subkeys.asc to Jenkins credentials"
  echo "  * Click on name 'secret-subkeys.asc'"
  echo "  * Update"
  echo "  * Select 'Replace' checkbox"
  echo "  * Browse"
  echo "  * Open folder '${SCRIPT_FOLDER}/${PROJECT_NAME}'"
  echo "  * Select file 'secret-subkeys.asc'"
  open_url "https://ci.eclipse.org/${SHORT_NAME}/credentials"
  echo "* Push changes to pass"
  read -rsp $'\nOnce you are done, press any key to continue...' -n1
  echo
  echo "* Add reply to ticket:"
  echo "The following credentials have been added to the ${DISPLAY_NAME} CI instance:"
  echo "  * OSSRH"
  echo "  * GPG"
  echo
  echo "The process for allowing deployments to OSSRH has been started. We are currently waiting for https://issues.sonatype.org/browse/OSSRH-XXXX to be resolved."
  read -rsp $'\nOnce you are done, press any key to continue...' -n1
}

# Main
create_ossrh_credentials

create_gpg_credentials

create_jenkins_credentials

#TODO: deploy/update Maven settings file automatically
echo
echo "TODO: Re-deploy JIRO instance to update Maven settings file."
read -rsp $'\nOnce you are done, press any key to continue...' -n1

rm -rf "${PROJECT_NAME}"

printf "\nDone.\n"