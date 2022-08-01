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


# TODO:
# * deal with multiple executions due to errors
#     * do not create github credentials if they already exist
# * add confirmations/questions
# * open websites
# * create webhooks
# * improve instructions

create_github_credentials() {
  echo "# Creating GitHub bot user credentials..."
  "${SCRIPT_FOLDER}/../pass/add_creds.sh" "github" "${PROJECT_NAME}" || true
  "${SCRIPT_FOLDER}/../pass/add_creds.sh" "github_ssh" "${PROJECT_NAME}" || true
}

set_up_github_account() {
  # automate?
  cat <<EOF

# Setting up GitHub bot account...
==================================
* Set up GitHub bot account (https://github.com/signup)
  * Take credentials from pass
* Verify email
* Add SSH public key to GitHub bot account (Settings -> SSh and GPG keys -> New SSH key)
* Create API and admin token (Settings -> Developer Settings -> Personal access tokens)
  * API token
    * Name:       Jenkins GitHub Plugin token https://ci.eclipse.org/${SHORT_NAME}
    * Expiration: No expiration
    * Scopes:     repo:status, public_repo, admin:repo_hook
  * Add token to pass (api-token)
* Add GitHub bot to project’s GitHub org (invite via webmaster account)
EOF
  read -rsp $'Once you are done, press any key to continue...\n' -n1

#TODO: read tokens from stdin and add them to pass

}

add_jenkins_credentials() {
#TODO: check that token credentials have been created
  printf "\n# Adding GitHub bot credentials to Jenkins instance...\n"
  "${JIRO_ROOT_FOLDER}/jenkins-create-credentials.sh" "${PROJECT_NAME}"
  "${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "auto" "${PROJECT_NAME}"
}

update_projects_bot_api() {
  printf "\n# Update projects-bots-api...\n"

  echo "Connected to cluster?"
  read -p "Press enter to continue or CTRL-C to stop the script"

  echo "Pulled latest version of projects-bots-api?"
  read -p "Press enter to continue or CTRL-C to stop the script"

  "${PROJECTS_BOTS_API_ROOT_FOLDER}/regen_db.sh"

  printf "\n\n"
#TODO: Show error if files are equal
  read -rsp $'Once you are done with comparing the diff, press any key to continue...\n' -n1
  "${PROJECTS_BOTS_API_ROOT_FOLDER}/deploy_db.sh"

  printf "\n# TODO: Double check that bot account has been added to API (https://api.eclipse.org/bots)...\n"
  read -rsp $'Once you are done, press any key to continue...\n' -n1
}

instructions_template() {
  printf "\n# Post instructions to GitLab...\n"
  cat <<EOF
Post the following on the corresponding GitLab issue:
-------------------------------------------------------
GitHub bot (ID: eclipse-${SHORT_NAME}-bot) has been created. Credentials have been added to the ${SHORT_NAME} JIPP.

To set up a job that builds pull requests, you can use a Freestyle job and the GitHub Pull Request Builder (GHPRB) Plugin.

The recommended way is to use a Multibranch Pipeline job instead (a Jenkinsfile in your repo is required):
1. New item > Multibranch Pipeline
2. Branch Sources > Add source > GitHub
3. Select credentials "GitHub bot (username/token)"
4. Add the repository URL
5. Configure behaviors 
6. Save

By default all branches and PRs will be scanned and dedicated build jobs will be created automatically (if a Jenkinsfile is found).

EOF
}

#### MAIN

create_github_credentials

set_up_github_account

update_projects_bot_api

add_jenkins_credentials

printf "\n# TODO: Set up GitHub config in Jenkins...\n"
printf "\n# TODO: Commit changes to pass...\n"

read -rsp $'Once you are done, press any key to continue...\n' -n1

instructions_template

