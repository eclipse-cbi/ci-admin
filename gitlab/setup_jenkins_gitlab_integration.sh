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
LOCAL_CONFIG="${HOME}/.cbi/config"

if [[ ! -f "${LOCAL_CONFIG}" ]]; then
  echo "ERROR: File '$(readlink -f "${LOCAL_CONFIG}")' does not exists"
  echo "Create one to configure the location of the JIRO root dir and the projects-bots-api root dir. Example:"
  echo '{"jiro-root-dir": "/path/to/jiro/rootdir"}'
  echo '{"projects-bots-api-root-dir": "/path/to/projects-bots-api/rootdir"}'
  exit 1
fi

JIRO_ROOT_FOLDER="$(jq -r '."jiro-root-dir"' < "${LOCAL_CONFIG}")"
PROJECTS_BOTS_API_ROOT_FOLDER="$(jq -r '."projects-bots-api-root-dir"' < "${LOCAL_CONFIG}")"

if [[ -z "${JIRO_ROOT_FOLDER}" ]] || [[ "${JIRO_ROOT_FOLDER}" == "null" ]]; then
  printf "ERROR: 'jiro-root-dir' must be set in %s.\n" "${LOCAL_CONFIG}"
  exit 1
fi

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

add_gitlab_jcasc_config() {
  mkdir -p "${JIRO_ROOT_FOLDER}/instances/${PROJECT_NAME}/jenkins"
#TODO: deal with existing configuration.yml file 
  cat <<EOF > "${JIRO_ROOT_FOLDER}/instances/${PROJECT_NAME}/jenkins/configuration.yml"
unclassified:
  gitLabConnectionConfig:
    connections:
    - apiTokenId: "gitlab-api-token"
      clientBuilderId: "autodetect"
      connectionTimeout: 10
      ignoreCertificateErrors: false
      name: "gitlab.eclipse.org"
      readTimeout: 10
      url: "https://gitlab.eclipse.org"
  gitLabServers:
    Servers:
    - credentialsId: "gitlab-personal-access-token"
      name: "gitlab.eclipse.org"
      serverUrl: "https://gitlab.eclipse.org"
EOF
  
  printf "\n# Reloading configuration of the Jenkins instance...\n"
  
  echo "Connected to cluster?"
  read -rsp "Press enter to continue or CTRL-C to stop the script"
  
  pushd "${JIRO_ROOT_FOLDER}"
  # TODO: deal with working directory
  ./jenkins-reload-jcasc-only.sh "instances/${PROJECT_NAME}"
  popd
}

add_bot_to_projects-bot-api() {
  # TODO: don't update if the bot has been added before
  printf "\n# Update projects-bots-api...\n"
  "${PROJECTS_BOTS_API_ROOT_FOLDER}/regen_db.sh"
  
  printf "\n\n"
  read -rsp $'Once you are done with comparing the diff, press any key to continue...\n' -n1
  "${PROJECTS_BOTS_API_ROOT_FOLDER}/deploy_db.sh"
}

instructions_template() {
  printf "\n# Post instructions to GitLab...\n"
  cat <<EOF
Post the following on the corresponding GitLab issue:
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

printf "\n# Adding GitLab bot credentials to Jenkins instance...\n"
"${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "gitlab" "${PROJECT_NAME}"
"${JIRO_ROOT_FOLDER}/jenkins-create-credentials.sh" "${PROJECT_NAME}"

printf "\n# Adding GitLab JCasC config to %s Jenkins instance...\n" "${PROJECT_NAME}"
add_gitlab_jcasc_config

add_bot_to_projects-bot-api

printf "\n# Adding bot to GitLab group...\n"
# TODO: read botname from pass?
bot_name="${SHORT_NAME}-bot"
group_name="${SHORT_NAME}"
access_level=40 # 40 = Maintainer
"${SCRIPT_FOLDER}/gitlab_admin.sh" "add_user_to_group" "${group_name}" "${bot_name}" "${access_level}"

# TODO: make optional?
printf "\n# Creating Webhooks...\n"
repo_name="${SHORT_NAME}" # this only works for the default repo
"${SCRIPT_FOLDER}/create_gitlab_webhook.sh" "${PROJECT_NAME}" "${repo_name}"

instructions_template

