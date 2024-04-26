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
  if [[ ! -f "${JIRO_CONFIG_FILE}" ]]; then
    touch "${JIRO_CONFIG_FILE}"
  fi
  output='.unclassified += {"gitLabConnectionConfig":{"connections":[{'
  output+='"apiTokenId": "gitlab-api-token",'
  output+='"clientBuilderId" : "autodetect",'
  output+='"connectionTimeout": 10,'
  output+='"ignoreCertificateErrors": false,'
  output+='"name": "gitlab.eclipse.org",'
  output+='"readTimeout": 10,'
  output+='"url": "https://gitlab.eclipse.org"}]},'
  output+='"gitLabServers": { "Servers": [ {'
  output+='"credentialsId": "gitlab-api-token",'
  output+='"name": "gitlab.eclipse.org",'
  output+='"serverUrl": "https://gitlab.eclipse.org",'
  output+='"webhookSecretCredentialsId": "gitlab-webhook-secret"}]}}'
  yq -i "${output}" "${JIRO_CONFIG_FILE}"

  printf "\n# Reloading configuration of the Jenkins instance...\n"

  echo "Connected to cluster?"
  read -rsp "Press enter to continue or CTRL-C to stop the script"

  pushd "${JIRO_ROOT_FOLDER}/incubation"
  # TODO: deal with working directory
  ./update_jcasc_config.sh "${JIRO_ROOT_FOLDER}/instances/${PROJECT_NAME}"
  popd
}

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

#TODO: create a group webhook instead
create_group_webhook() {
  group_name="${SHORT_NAME}" # this only works for the default group
  printf "\n# Creating group webhook for group '${group_name}'...\n"
  "${SCRIPT_FOLDER}/create_gitlab_webhook.sh" "group" "${PROJECT_NAME}" "${group_name}"
  "${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "gitlab_webhook_secret" "${PROJECT_NAME}"
}

instructions_template() {
  printf "\n# Post instructions to GitLab...\n"
  cat <<EOF

Post the following on the corresponding HelpDesk issue:
-------------------------------------------------------

A GitLab bot user for ${PROJECT_NAME} has been created, along with credentials that have been added to the CI instance (SSH credentials ID: \`gitlab-bot-ssh\`).
A webhook that will trigger CI jobs has been added as well.

[jenkins pipeline best practice](https://github.com/eclipse-cbi/jiro/wiki/Jenkins#jenkins-pipeline-best-practices) and we encourage the following:
* Utilize \`Jenkinsfile\`: it allows to define an entire pipeline as code by managing build process declaratively or with scripted syntax, making pipeline configuration version-controlled and therefore reproducible. Learn more about Jenkinsfile [here](https://www.jenkins.io/doc/book/pipeline/jenkinsfile/).
* In addition \`Multibranch Pipeline\`: automatically creates a pipeline for each branch/merge request of a repository. This approach simplifies branch management and enables automated branch-based builds and testing. More about Multibranch Pipeline [here](https://www.jenkins.io/doc/book/pipeline/multibranch/).

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

add_jenkins_credentials() {
  printf "\n# Adding GitLab bot credentials to Jenkins instance...\n"
  "${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "gitlab" "${PROJECT_NAME}"
  "${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "gitlab_pat" "${PROJECT_NAME}"
  "${JIRO_ROOT_FOLDER}/jenkins-create-credentials.sh" "${PROJECT_NAME}"
}

#### MAIN

echo "# Creating a GitLab bot user..."
"${SCRIPT_FOLDER}/create_gitlab_bot_user.sh" "${PROJECT_NAME}"

add_bot_to_group

update_projects_bot_api

#check if project has a Jenkins instance
if [[ -d "${JIRO_ROOT_FOLDER}/instances/${PROJECT_NAME}" ]]; then
  printf "\nFound Jenkins instance for %s...\n" "${PROJECT_NAME}"
  _question_action "add Jenkins credentials" add_jenkins_credentials
  echo
  _question_action "create a group webhook" create_group_webhook
  echo
  _question_action "add GitLab JCasC config" add_gitlab_jcasc_config
  instructions_template
fi

printf "\n\n# TODO: Commit changes to pass...\n"
read -rsp $'Once you are done, press any key to continue...\n' -n1
