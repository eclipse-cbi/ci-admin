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

NAME="${1:-}"
PROJECT="${2:-}"
ORGANIZATION="${3:-}"

SONAR_API_BASE_URL="https://sonarcloud.io/api"

if [[ ! -f "${SCRIPT_FOLDER}/../.localconfig" ]]; then
  echo "ERROR: File '$(readlink -f "${SCRIPT_FOLDER}/../.localconfig")' does not exists"
  echo "Create one to configure the sonar token. Example:"
  echo '{"sonar-token": "abcdefgh1234567890"}'
fi

SONAR_TOKEN="$(cat "${SCRIPT_FOLDER}/../.localconfig" | jq -r '."sonar-token"')"

if [ -z "${NAME}" ]; then
  printf "ERROR: a name (e.g. 'Eclipse CBI Project' for CBI project) must be given.\n" >&2
  exit 1
fi

if [ -z "${PROJECT}" ]; then
  printf "ERROR: a project (e.g. 'org.eclipse:cbi') must be given.\n" >&2
  exit 1
fi

if [ -z "${ORGANIZATION}" ]; then
  printf "ERROR: an organization (e.g. 'eclipse') must be given.\n" >&2
  exit 1
fi

if [ -z "${SONAR_TOKEN}" -o "${SONAR_TOKEN}" == "null" ]; then
  printf "ERROR: sonar token needs to be set in .localconfig.\n" >&2
  exit 1
fi



curl_post() {
  local data="$1"
  local api_path="$2"

     #--include \
  curl -sSL \
     --request POST \
     --header "Content-Type: application/x-www-form-urlencoded" \
     -u "${SONAR_TOKEN}": \
     -d "${data}" \
    "${SONAR_API_BASE_URL}/${api_path}"
}

create_token() {
  local name="$1"

  echo "Creating SonarCloud token:"
  reply="$(curl_post "name=${name}" 'user_tokens/generate')"
  #echo "${reply}" #debug

  # deal with errors (e.g. token exists already)"
  if echo "${reply}" | jq -e 'has("errors")' > /dev/null ; then
    echo "${reply}" | jq -r '.errors[].msg'
  else
    echo "${reply}" | jq -r '.token'
  fi
}


create_project() {
  local sonar_name="$1"
  local sonar_project="$2"
  local sonar_organization="$3"

  echo "Creating SonarCloud project ${sonar_project}:"
  curl_post "name=${sonar_name}&project=${sonar_project}&organization=${sonar_organization}" 'projects/create' | jq .
}

create_project "${NAME}" "${PROJECT}" "${ORGANIZATION}"
create_token "Token for ${PROJECT}"

