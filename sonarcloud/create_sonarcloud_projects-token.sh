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

PROJECT_NAME="${1:-}"

# check that project name is not empty
if [[ -z "${PROJECT_NAME}" ]]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

SHORT_NAME="${PROJECT_NAME##*.}"
SONAR_ORG="${2:-eclipse-${SHORT_NAME}}"

SONAR_API_BASE_URL="https://sonarcloud.io/api"
DRY_RUN=false

#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../pass/pass_wrapper.sh"

SONAR_TOKEN="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "sonar-token")"
JIRO_ROOT_DIR="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "jiro-root-dir")"

if [ -z "${SONAR_TOKEN}" ] || [ "${SONAR_TOKEN}" == "null" ]; then
  printf "ERROR: sonar token ('sonar-token') needs to be set in %s.\n" "${LOCAL_CONFIG}" >&2
  exit 1
fi

if [ -z "${JIRO_ROOT_DIR}" ] || [ "${JIRO_ROOT_DIR}" == "null" ]; then
  printf "ERROR: JIRO root dir ('jiro-root-dir') needs to be set in %s.\n" "${LOCAL_CONFIG}" >&2
  exit 1
fi

curl_post() {
  local data="$1"
  local api_path="$2"

  if ! ${DRY_RUN}; then
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

curl_get() {
  local api_path="$1"
  local api_opts="$2"

  if ! ${DRY_RUN}; then
    curl -sSL \
      --request GET \
      --header "Content-Type: application/x-www-form-urlencoded" \
      -u "${SONAR_TOKEN}": \
     "${SONAR_API_BASE_URL}/${api_path}?${api_opts}"
  else
    echo "DRY-RUN: curl -sSL --request POST --header \"Content-Type: application/x-www-form-urlencoded\" -u \"${SONAR_TOKEN}\": -d \"${data}\" \"${SONAR_API_BASE_URL}/${api_path}\"" >&2
    echo "{}"
  fi
}

get_projects() {
  local sonar_organization="$1"
  curl_get  "projects/search" "organization=${sonar_organization}&ps=500"| jq -r '.components[].key'
}

create_token() {
  local token_name="Analyze \"${1:-}\""
  local suffix="${2:-}"

  echo "Creating SonarCloud token:"
  reply="$(curl_post "name=${token_name}" 'user_tokens/generate')"
  if echo "${reply}" | jq -e 'has("errors")' > /dev/null ; then
    echo "${reply}" | jq -r '.errors[].msg'
  else
    token="$(echo "${reply}" | jq -r '.token')"
    if ! ${DRY_RUN}; then
      echo "${token}" | passw cbi insert --echo "bots/${PROJECT_NAME}/sonarcloud.io/token${suffix}"
    else
      echo "DRY-RUN: passw cbi insert --echo \"bots/${PROJECT_NAME}/sonarcloud.io/token${suffix}\""
    fi
  fi
}

deactivate_autoscan() {
  local projectKey="${1:-}"

  echo "Deactivate SonarCloud autoscan on project ${projectKey}"
  reply="$(curl_post "projectKey=${projectKey}&enable=false" 'autoscan/activation')"

  if echo "${reply}" | jq -e 'has("errors")' > /dev/null ; then
    echo "${reply}" | jq -r '.errors[].msg'
  else
    echo "Autoscan deactivated on ${projectKey}"
  fi
}

process_projects() {
  local sonar_organization="$1"

  local keys
  keys=$(get_projects "$sonar_organization" )

  for key in $keys; do
    project=${key##*_}
    echo "Project: ${project}"
    if [[ "$project" =~ ^(.github|.eclipsefdn)$ ]]; then
      echo "Skipping project: ${project}"
      continue
    fi
    create_token "${key}" "-${project}"
    deactivate_autoscan  "${key}"
  done
}

process_projects "${SONAR_ORG}"
