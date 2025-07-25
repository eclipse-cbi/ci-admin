#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2020 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Create sonarcloud.io project

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'
SCRIPT_FOLDER="$(dirname "$(readlink -f "${0}")")"
SCRIPT_NAME="$(basename "${0}")"

PROJECT_NAME="${1:-}"
SONAR_NAME="${2:-}"
SONAR_PROJECT="${3:-}"
SONAR_ORG="${4:-eclipse}"

SHORT_NAME="${PROJECT_NAME##*.}"

SONAR_API_BASE_URL="https://sonarcloud.io/api"
DRY_RUN=false

#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../pass/pass_wrapper.sh"
LOCAL_CONFIG="${HOME}/.cbi/config"
SONAR_TOKEN="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "sonar-token")"
JIRO_ROOT_DIR="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "jiro-root-dir")"

usage() {
  printf "Usage: %s project_name sonar_name sonar_project_id [sonar_org]\n" "${SCRIPT_NAME}"
  printf "\t%-16s project name (e.g. technology.cbi for CBI project).\n" "project_name"
  printf "\t%-16s sonar_name (e.g. 'Eclipse CBI Project' for CBI project).\n" "sonar_name"
  printf "\t%-16s sonar_project (e.g. 'org.eclipse.cbi').\n" "sonar_project"
  printf "\t%-16s sonar_org (optional, default is 'eclipse').\n" "sonar_org"
}

if [ -z "${SONAR_TOKEN}" ] || [ "${SONAR_TOKEN}" == "null" ]; then
  printf "ERROR: sonar token ('sonar-token') needs to be set in %s.\n" "${LOCAL_CONFIG}" >&2
  exit 1
fi

if [ -z "${JIRO_ROOT_DIR}" ] || [ "${JIRO_ROOT_DIR}" == "null" ]; then
  printf "ERROR: JIRO root dir ('jiro-root-dir') needs to be set in %s.\n" "${LOCAL_CONFIG}" >&2
  exit 1
fi


if [ -z "${PROJECT_NAME}" ]; then
  printf "ERROR: a project name (e.g. 'technology.cbi' for the CBI project) must be given.\n" >&2
  usage
  exit 1
fi

if [ -z "${SONAR_NAME}" ]; then
  printf "ERROR: a name (e.g. 'Eclipse CBI Project' for the CBI project) must be given.\n" >&2
  usage
  exit 1
fi

if [ -z "${SONAR_PROJECT}" ]; then
  printf "ERROR: a project (e.g. 'org.eclipse.cbi') must be given.\n" >&2
  usage
  exit 1
fi

if [ -z "${SONAR_ORG}" ]; then
  printf "ERROR: an organization (e.g. 'eclipse') must be given.\n" >&2
  usage
  exit 1
fi


curl_post() {
  local data="$1"
  local api_path="$2"

  if ! ${DRY_RUN}; then
     #--include \
    curl -sSL \
      --request POST \
      --header "Content-Type: application/x-www-form-urlencoded" \
      -u "${SONAR_TOKEN}": \
      -d "${data}" \
     "${SONAR_API_BASE_URL}/${api_path}"
  else
    echo "DRY-RUN: curl -sSL --request POST --header \"Content-Type: application/x-www-form-urlencoded\" -u \"${SONAR_TOKEN}\": -d \"${data}\" \"${SONAR_API_BASE_URL}/${api_path}\"" >&2
    echo "{}"
  fi
}

create_project() {
  local sonar_name="$1"
  local sonar_project="$2"
  local sonar_organization="$3"

  echo "Creating SonarCloud project ${sonar_project}:"
  curl_post "name=${sonar_name}&project=${sonar_project}&organization=${sonar_organization}" 'projects/create' | jq .
}

create_token() {
  local token_name="Token for ${1:-}"
  local suffix="${2:-}"

  echo "Creating SonarCloud token:"
  reply="$(curl_post "name=${token_name}" 'user_tokens/generate')"
  #echo "${reply}" #debug

  # deal with errors (e.g. token exists already)"
  if echo "${reply}" | jq -e 'has("errors")' > /dev/null ; then
    echo "${reply}" | jq -r '.errors[].msg'
  else
    token="$(echo "${reply}" | jq -r '.token')"
    echo "${token}"
    # Add token to pass
    if ! ${DRY_RUN}; then
      echo "${token}" | passw cbi insert --echo "bots/${PROJECT_NAME}/sonarcloud.io/token${suffix}"
    else
      echo "DRY-RUN: passw cbi insert --echo \"bots/${PROJECT_NAME}/sonarcloud.io/token${suffix}\""
    fi
  fi
}

create_issue_template() {
  local ci="${1:-}"
  # create issue response template
  echo ""
  echo "Issue response template:"
  echo "========================"
  echo
  echo "https://sonarcloud.io/dashboard?id=${SONAR_PROJECT} is set up now."

  if "${ci}"; then
  cat <<EOF
https://sonarcloud.io/dashboard?id=${SONAR_PROJECT} is set up now.

The ${SHORT_NAME} Jenkins instance has been configured accordingly.

To set up a job that runs the SonarCloud analysis, please follow these steps:

In your job config
*  Enable "Use secret text(s) or file(s)"
    Add -> Secret text
    Select "SonarCloud token for ${SHORT_NAME}${SUFFIX}"
    Variable: SONARCLOUD_TOKEN
* Enable "Prepare SonarQube Scanner environment" option
* In Maven build step,
  Goals: clean verify -B sonar:sonar
-Dsonar.projectKey=${SONAR_PROJECT}
-Dsonar.organization=${SONAR_ORG}
-Dsonar.host.url=\${SONAR_HOST_URL}
-Dsonar.login=\${SONARCLOUD_TOKEN}
EOF
  else
    printf "\n\nTODO: add token to GitHub repo/org secret\n\n"
  fi
}


## MAIN

create_project "${SONAR_NAME}" "${SONAR_PROJECT}" "${SONAR_ORG}"

echo -n "${SONAR_PROJECT} suffix?: "; read -r SUFFIX
if [[ -n "${SUFFIX}" ]]; then
  SUFFIX="-${SUFFIX}"
else
  SUFFIX=""
fi

create_token "${SONAR_PROJECT}" "${SUFFIX}"

# add SonarCloud credentials to Jenkins instance

if [[ -d "${JIRO_ROOT_DIR}/instances/${PROJECT_NAME}" ]]; then
  printf "\nCreating SonarCloud credentials in %s CI instance...\n" "${SHORT_NAME}"
  "${JIRO_ROOT_DIR}/jenkins-create-credentials-token.sh" "sonarcloud" "${PROJECT_NAME}" "${SUFFIX}"
  ci=true
else
  printf "\nNo Jiro instance found for %s CI instance. Skipping...\n" "${SHORT_NAME}"
  ci=false
fi

create_issue_template "${ci}"
