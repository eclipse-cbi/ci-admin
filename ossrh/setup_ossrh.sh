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
  _open_url "https://issues.sonatype.org/secure/Signup!default.jspa"
  printf "\n* Login with new OSSRH account\n"
  read -rsp $'\nOnce you are done, press any key to continue...' -n1
  printf "\n* Create an issue here: https://issues.sonatype.org/secure/CreateIssue.jspa?issuetype=21&pid=10134\n"
  _open_url "https://issues.sonatype.org/secure/CreateIssue.jspa?issuetype=21&pid=10134"
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
  local pw_store_path="bots/${PROJECT_NAME}/gpg"
  # check that the entries do not exist yet
  if passw cbi "${pw_store_path}" &> /dev/null ; then
    printf "GPG credentials for %s already exist. Skipping creation...\n" "${PROJECT_NAME}"
    return
  fi
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
  _open_url "https://ci.eclipse.org/${SHORT_NAME}/credentials"
  echo "* Push changes to pass"
  read -rsp $'\nOnce you are done, press any key to continue...' -n1
  echo
  echo "* Add reply to ticket:"
  echo "The following credentials have been added to the ${DISPLAY_NAME} CI instance:"
  echo "  * OSSRH"
  echo "  * GPG"
  read -rsp $'\nOnce you are done, press any key to continue...' -n1
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

Issue comment template for HelpDesk issue after the OSSRH ticket has been created but is not resolved yet:
----------------------------------------------------------------------------------------------------------

The process for allowing deployments to OSSRH has been started. We are currently waiting for https://issues.sonatype.org/browse/OSSRH-XXXX to be resolved.



Issue comment template for HelpDesk issue once the OSSRH ticket is resolved (usually takes a few hours):
--------------------------------------------------------------------------------------------------------

https://issues.sonatype.org/browse/OSSRH-XXXX is resolved now.

The default Maven settings contain a server definition named 'ossrh' to let you upload things to Sonatype's server.
This server id should be used in a distributionManagement repository somewhere specifying the URL.
See http://central.sonatype.org/pages/ossrh-guide.html#releasing-to-central and http://central.sonatype.org/pages/ossrh-guide.html#ossrh-usage-notes for details.
The GPG passphrase is also configured (encrypted) in the settings (as described at
https://maven.apache.org/plugins/maven-gpg-plugin/usage.html#Configure_passphrase_in_settings.xml). It's recommended to use the maven-gpg-plugin.
See also https://wiki.eclipse.org/Jenkins#How_can_artifacts_be_deployed_to_OSSRH_.2F_Maven_Central.3F

Let us know when you promoted your first release, so we can comment on
https://issues.sonatype.org/browse/OSSRH-XXXX. Or you can do this yourself.

EOF

}

# Main
create_ossrh_credentials

create_gpg_credentials

_question_action "create Jenkins credentials" create_jenkins_credentials
echo
_question_action "regenerate Maven settings for Jenkins" regen_maven_settings

ossrh_comment_template
read -rsp $'\nOnce you are done, press any key to continue...' -n1

rm -rf "${PROJECT_NAME}"

printf "\nDone.\n"