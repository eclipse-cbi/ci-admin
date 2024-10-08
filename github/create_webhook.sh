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

CI_ADMIN_ROOT="${SCRIPT_FOLDER}/.."
LOCAL_TOKEN="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "access_token" "github")"

help() {
  printf "Available commands:\n"
  printf "Command\t\tDescription\n\n"
  printf "org\t\tCreate webhook on organization level.\n"
  printf "repo\t\tCreate webhook on repo level.\n"
  exit 0
}

create_github_hook() {
  local token="$1"
  local type="$2"
  local org="$3"
  local webhook_url="$4"
  local events="$5"
  
  curl -sS \
    -w "\n%{http_code}" \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${token}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/${type}/${org}/hooks" \
    -d '{"name":"web","active":true,"events":'${events}',"config":{"url":"'${webhook_url}'","content_type":"json"}}'
}

process_response() {
  local response="$1"
  local message="$2"  
  local http_code
  local content
  
  http_code=$(echo "${response}" | tail -n 1)
  content=$(echo "${response}" | head -n -1)
  
  case "${http_code}" in
    201)
      echo "INFO: Webhook created successfully with ${message}."
      return 0
      ;;
    422)
      echo "INFO: Webhook already exists for ${message}."
      return 0
      ;;
    *)
      echo "ERROR: Failed to create webhook with ${message}. Check org/repo permissions and if the token has the ability to create webhooks."
      printf " Message: %s\n" "$(echo "${content}" | jq '.message')"
      return 1
      ;;
  esac
}

create_hook() {
  local project_name="${1:-}"
  local org="${2:-}"
  local hook_type="${3:-}"

  local short_name="${project_name##*.}"
  local webhook_url="https://ci.eclipse.org/${short_name}/github-webhook/"
  local events='["push","pull_request"]'
  
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

  bot_token=$(passw cbi "bots/${project_name}/${GITHUB_PASS_DOMAIN}/api-token")

  echo "Creating organization webhook..."

  response=$(create_github_hook "${bot_token}" "${hook_type}" "${org}" "${webhook_url}" "${events}")
  if ! process_response "${response}" "${project_name} project and bot token"; then
    echo "INFO: Try with CBI token"
    response=$(create_github_hook "${LOCAL_TOKEN}" "${hook_type}" "${org}" "${webhook_url}" "${events}")
    if ! process_response "${response}" "${project_name} project and cbi config token"; then
      echo "ERROR: Failed to create webhook for ${project_name} project."
      exit 1
    fi
  fi
}

org() {
  create_hook "$1" "$2" "orgs"
}

repo() {
  create_hook "$1" "$2" "repos"
}

"$@"

#TODO: check that only the listed commands are used

# show help menu, if no first parameter is given
if [[ -z "${1:-}" ]]; then
  help
fi


  