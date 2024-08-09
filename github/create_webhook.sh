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

SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../pass/pass_wrapper.sh"

GITHUB_PASS_DOMAIN="github.com"

#shellcheck disable=SC2089
EVENTS='["push","pull_request"]'

help() {
  printf "Available commands:\n"
  printf "Command\t\tDescription\n\n"
  printf "org\t\tCreate webhook on organization level.\n"
  printf "repo\t\tCreate webhook on repo level.\n"
  exit 0
}

org() {
  local project_name="${1:-}"
  local org="${2:-}"
  local short_name="${project_name##*.}"
  local webhook_url="https://ci.eclipse.org/${short_name}/github-webhook/"

  # check that project name is not empty
  if [[ -z "${project_name}" ]]; then
    printf "ERROR: a project name must be given.\n"
    exit 1
  fi
  
  # check that org name is not empty
  if [[ -z "${org}" ]]; then
    printf "ERROR: a GitHub organization name must be given.\n"
    exit 1
  fi

  local pw_store_path="bots/${project_name}/${GITHUB_PASS_DOMAIN}"
  local bot_token=$(passw cbi "${pw_store_path}/api-token")

  echo "Creating organization webhook..."

  local response
  response="$(curl -sS\
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${bot_token}"\
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/orgs/${org}/hooks" \
    -d '{"name":"web","active":true,"events":'${EVENTS}',"config":{"url":"'${webhook_url}'","content_type":"json"}}')"
  
  if [[ "$(echo "${response}" | jq .errors)" != "null" ]] || [[ "$(echo "${response}" | jq .message)" != "null" ]]; then
    echo "ERROR:"
    printf " Message: %s\n" "$(echo "${response}" | jq '.message')"
    printf " Errors/Message: %s\n" "$(echo "${response}" | jq '.errors[].message')"
    exit 1
  fi
}

repo() {
  local project_name="${1:-}"
  local repo="${2:-}" # org/repo
  local short_name="${project_name##*.}"
  local webhook_url="https://ci.eclipse.org/${short_name}/github-webhook/"


  # check that project name is not empty
  if [[ -z "${project_name}" ]]; then
    printf "ERROR: a project name must be given.\n"
    exit 1
  fi
  
  # check that repo name is not empty
  if [[ -z "${repo}" ]]; then
    printf "ERROR: a GitHub repo name (org/repo) must be given.\n"
    exit 1
  fi

  local pw_store_path="bots/${project_name}/${GITHUB_PASS_DOMAIN}"
  local bot_token=$(passw cbi "${pw_store_path}/api-token")

  echo "Creating repo webhook..."

  local response
  response="$(curl -sS\
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${bot_token}"\
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${repo}/hooks" \
    -d '{"name":"web","active":true,"events":'${EVENTS}',"config":{"url":"'${webhook_url}'","content_type":"json"}}')"
  
  if [[ "$(echo "${response}" | jq .errors)" != "null" ]] || [[ "$(echo "${response}" | jq .message)" != "null" ]]; then
    echo "ERROR:"
    printf " Message: %s\n" "$(echo "${response}" | jq '.message')"
    printf " Errors/Message: %s\n" "$(echo "${response}" | jq '.errors[].message')"
  else
    echo "Webhook created."
  fi
}

"$@"

#TODO: check that only the listed commands are used

# show help menu, if no first parameter is given
if [[ -z "${1:-}" ]]; then
  help
fi


  