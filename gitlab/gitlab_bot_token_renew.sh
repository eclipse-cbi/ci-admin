#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2024 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Create bot user in GitLab and set up SSH key

# Bash strict-mode
# set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'
SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
CI_ADMIN_ROOT="${SCRIPT_FOLDER}/.."
JIRO_ROOT_FOLDER="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "jiro-root-dir")"
OTTERDOG_CONFIGS_ROOT="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "otterdog-configs-root-dir")"
GITLAB_PASS_DOMAIN="gitlab.eclipse.org"

#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../pass/pass_wrapper.sh"
#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../utils/common.sh"

set +o errexit

export VAULT_ADDR=${VAULT_ADDR:-https:\/\/secretsmanager.eclipse.org}
export VAULT_AUTH_METHOD=${VAULT_AUTH_METHOD:-token}
export VAULT_TOKEN=${VAULT_TOKEN:-""}

VAULT_MOUNT_PATH="cbi"

usage() {
  cat << EOF # remove the space between << and EOF, this is due to web plugin issue
Usage: $(basename "${BASH_SOURCE[0]}") <project_id> [-h] [-v] [-f] [-t]

Renew GitLab API token for the bot user of the project <project_id> or all projects bots registered in the secretsmanager.

e.g: 
* gitlab_bot_token_renew.sh technology.cbi -f # Renew the token and update tools for the project technology.cbi
* gitlab_bot_token_renew.sh -f # Renew the token and update tools for all projects bots registered in the secretsmanager

Available options:

-h  Help
-v  Verbose mode

# Script params: 
-f  FORCE_UPDATE: Force update token and tools for the project
-t  FORCE_TOOLS_UPDATE: Force update tools for the project

EOF
  exit
}

FORCE_UPDATE=""
FORCE_TOOLS_UPDATE=""
PARAM=${1:-}

if [[ -n "${PARAM}" ]] && [[ "${PARAM}" =~ ^- ]]; then
  OPTIND=1
else
  OPTIND=2
fi 

while getopts ":hvtf" option; do
  case $option in
  h) usage ;;
  v) set -x ;;
  f)
    FORCE_UPDATE="true"
    ;;
  t)
    FORCE_TOOLS_UPDATE="true"
    ;;
  :)
    echo "ERROR: the option -$OPTARG need an argument." >&2
    exit 1
    ;;
  -?*) echo "Unknown option: $1" && exit 1 ;;
  *) break ;;
  esac
done

if ! vault token lookup > /dev/null; then
    echo "Check your token validity and export VAULT_TOKEN"
    exit 1
fi

if ! vault kv list -mount="${VAULT_MOUNT_PATH}" > /dev/null; then
    echo "Error accessing the secret mount: ${VAULT_MOUNT_PATH}}"
    exit 1
fi

if [[ ${FORCE_UPDATE} == "true" ]]; then
  echo "WARN: Force update token and tools"
fi  
if [[ ${FORCE_TOOLS_UPDATE} == "true" ]]; then
  echo "WARN: Force update tools"
fi

# Renew all tokens for all projects registered in Vault
renew_all_tokens() {
    projects=$(vault kv list -mount="${VAULT_MOUNT_PATH}" -format=json)
    if [ "$?" -ne 0 ]; then
        echo "ERROR: listing secrets at mount: ${VAULT_MOUNT_PATH}}"
        return 1
    fi
    for project in $(echo "${projects}" | jq -r '.[]'); do
        local project_id="${project%/}"
        renew_token "${project_id}"
    done
}

# Check if the API token is still valid and renew it if necessary
renew_token() {
    local project_id="${1:-}"
    echo "############### Check project: ${project_id} ###############"
    token=$(vault kv get -mount="${VAULT_MOUNT_PATH}" -field="api-token" "${project_id}/gitlab.eclipse.org" 2>/dev/null) || true
    [[ -z "$token" ]] && echo "No GitLab api token found for ${project_id}" && return
    
    username=$(vault kv get -mount="${VAULT_MOUNT_PATH}" -field="username" "${project_id}/gitlab.eclipse.org" 2>/dev/null) || true        
    if [[ "${FORCE_UPDATE}" == "true" ]]; then
        revoke_token "${project_id}" "${username}"
        create_token "${project_id}" "${username}"
        update_tools "${project_id}"
        return
    fi
    if "${SCRIPT_FOLDER}/gitlab_admin.sh" check_api_token_validity "${username}"; then
        if [[ -z "${FORCE_TOOLS_UPDATE}" ]]; then
            update_tools_answer=$(_question_true_false "Force update tools for ${project_id}")
            if [[ "${update_tools_answer}" == "true" ]];then
                update_tools "${project_id}"
            fi
        elif [[ "${FORCE_TOOLS_UPDATE}" == "true" ]]; then
            update_tools "${project_id}" 
        else
            echo "No tools update for ${project_id}"
        fi
    else
        create_token "${project_id}" "${username}"   
        update_tools "${project_id}"             
    fi
}

update_tools() {
    local project_id="${1:-}"
    if [[ -z "${project_id}" ]]; then
        echo "No project_id provided"
        return 1
    fi
    update_jenkins "${project_id}"
    update_otterdog "${project_id}"
}

# Create a new API token for the bot user
create_token() {
    local project_id="${1:-}"
    local username="${2:-}"
    echo "####### Create API token for project ${project_id} and user ${username} #######"
    token="$("${SCRIPT_FOLDER}/gitlab_admin.sh" "create_api_token" "${username}")"
    echo "Adding API token to pass: bots/${project_id}/${GITLAB_PASS_DOMAIN}/api-token"
    echo "${token}" | passw cbi insert --echo "bots/${project_id}/${GITLAB_PASS_DOMAIN}/api-token"
}

revoke_token() {
    local project_id="${1:-}"
    local username="${2:-}"
    echo "####### Revoke API token for project ${project_id} and user ${username} #######"
    "${SCRIPT_FOLDER}/gitlab_admin.sh" "revoke_api_token" "${username}"
}

# Update Jenkins configuration
update_jenkins() {
    local project_id="${1:-}"
    echo "####### Update Jenkins configuration for ${project_id} #######"
    if [[ -d "${JIRO_ROOT_FOLDER}/instances/${project_id}" ]]; then
        echo "Recreate token in Jenkins instance for ${project_id}"
        "${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "gitlab" "${project_id}"
        "${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "gitlab_pat" "${project_id}"
    else
        echo "WARN: No Jenkins instance found for ${project_id}"
    fi
}

# Update Otterdog configuration
update_otterdog() {
    local project_id="${1:-}"
    echo "####### Update Otterdog configuration for ${project_id} #######"
    pushd "${OTTERDOG_CONFIGS_ROOT}" > /dev/null
    otterdog_conf=$(jq  --arg project_id "$project_id" '.organizations[] | select(.name == $project_id)' < otterdog.json)
    if [[ -n "${otterdog_conf}" ]]; then
        github_id=$(echo "$otterdog_conf" | jq -r '.github_id')
        echo "Update api token with Otterdog for ${project_id}(${github_id})"
        PASSWORD_STORE_DIR="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "cbi-dir" "password-store")"
        export PASSWORD_STORE_DIR
        otterdog fetch-config -f "${github_id}"
        otterdog apply -f "${github_id}" -n --update-secrets --update-filter "*GITLAB_API_TOKEN"
    else
        echo "WARN: No Otterdog configuration found for ${project_id}"
    fi
    popd > /dev/null
}

if [[ -z "${PARAM}" || "${PARAM}" =~ ^- ]]; then
    renew_all_tokens
else 
    renew_token "${PARAM}"
fi
