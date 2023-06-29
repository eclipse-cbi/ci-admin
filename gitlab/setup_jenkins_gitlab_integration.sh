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
SHORT_NAME="${PROJECT_NAME##*.}"

# check that project name is not empty
if [[ -z "${PROJECT_NAME}" ]]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

add_gitlab_jcasc_config() {
  printf "\n# Adding GitLab JCasC config to %s Jenkins instance...\n" "${PROJECT_NAME}"
  mkdir -p "${JIRO_ROOT_FOLDER}/instances/${PROJECT_NAME}/jenkins"
  JIRO_CONFIG_FILE="${JIRO_ROOT_FOLDER}/instances/${PROJECT_NAME}/jenkins/configuration.yml"

  yq -i '.unclassified.gitLabConnectionConfig.connections.apiTokenId = "gitlab-api-token"' "${JIRO_CONFIG_FILE}"
  yq -i '.unclassified.gitLabConnectionConfig.connections.clientBuilderId = "autodetect"' "${JIRO_CONFIG_FILE}"
  yq -i '.unclassified.gitLabConnectionConfig.connections.connectionTimeout = 10' "${JIRO_CONFIG_FILE}"
  yq -i '.unclassified.gitLabConnectionConfig.connections.ignoreCertificateErrors = false' "${JIRO_CONFIG_FILE}"
  yq -i '.unclassified.gitLabConnectionConfig.connections.name = "gitlab.eclipse.org"' "${JIRO_CONFIG_FILE}"
  yq -i '.unclassified.gitLabConnectionConfig.connections.readTimeout = 10' "${JIRO_CONFIG_FILE}"
  yq -i '.unclassified.gitLabConnectionConfig.connections.url = "https://gitlab.eclipse.org"' "${JIRO_CONFIG_FILE}"

  yq -i '.unclassified.gitLabServers.Servers.credentialsId = "gitlab-personal-access-token"' "${JIRO_CONFIG_FILE}"
  yq -i '.unclassified.gitLabServers.Servers.name = "gitlab.eclipse.org"' "${JIRO_CONFIG_FILE}"
  yq -i '.unclassified.gitLabServers.Servers.serverUrl = "https://gitlab.eclipse.org"' "${JIRO_CONFIG_FILE}"
  yq -i '.unclassified.gitLabServers.Servers.webhookSecretCredentialsId = "gitlab-webhook-secret"' "${JIRO_CONFIG_FILE}"

  printf "\n# Reloading configuration of the Jenkins instance...\n"

  echo "Connected to cluster?"
  read -rsp "Press enter to continue or CTRL-C to stop the script"

  pushd "${JIRO_ROOT_FOLDER}/incubation"
  # TODO: deal with working directory
  ./update_jcasc_config.sh "${JIRO_ROOT_FOLDER}/instances/${PROJECT_NAME}"
  popd
}

update_projects_bot_api() {
  printf "\n# Updating projects-bots-api...\n"
  "${PROJECTS_BOTS_API_ROOT_FOLDER}"/regen_db.sh
}

add_bot_to_group() {
  printf "\n# Adding bot to GitLab group...\n"
  # TODO: read botname from pass?
  bot_name="${SHORT_NAME}-bot"
  group_name="${SHORT_NAME}"
  access_level=40 # 40 = Maintainer
  "${SCRIPT_FOLDER}/gitlab_admin.sh" "add_user_to_group" "${group_name}" "${bot_name}" "${access_level}"
}

#TODO: create a group webhook instead
create_group_webhook() {
  group_name="${SHORT_NAME}" # this only works for the default group
  printf "\n# Creating group webhook for group '${group_name}'...\n"
  "${SCRIPT_FOLDER}/create_gitlab_webhook.sh" "group" "${PROJECT_NAME}" "${group_name}"
}

instructions_template() {
  printf "\n# Post instructions to GitLab...\n"
  cat <<EOF

Post the following on the corresponding HelpDesk issue:
-------------------------------------------------------

A GitLab bot user for ${PROJECT_NAME} has been created along with credentials that have been added to the CI instance.
A webhook that will trigger CI jobs has been added as well.

The recommended way of creating a GitLab triggered job and handle merge request is as follows:
* create a Multi-branch pipeline job
* in your job config under "Branch Sources > Add source" select "GitLab project"
* select Checkout Credentials: "${SHORT_NAME}-bot (GitLab bot (SSH))"
* select Owner: eclipse/${SHORT_NAME}
* select Projects: e.g. eclipse/${SHORT_NAME}/${SHORT_NAME}
* select branches to build, etc

EOF
  read -rsp $'Once you are done, press any key to continue...\n' -n1
}

####

echo "# Creating a GitLab bot user..."
"${SCRIPT_FOLDER}/create_gitlab_bot_user.sh" "${PROJECT_NAME}"

update_projects_bot_api

add_bot_to_group

printf "\n# Adding GitLab bot credentials to Jenkins instance...\n"
"${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "gitlab" "${PROJECT_NAME}"
"${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "gitlab_pat" "${PROJECT_NAME}"
"${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "gitlab_webhook_secret" "${PROJECT_NAME}"
"${JIRO_ROOT_FOLDER}/jenkins-create-credentials.sh" "${PROJECT_NAME}"

add_gitlab_jcasc_config

_question_action "create a group webhook" create_group_webhook

instructions_template

