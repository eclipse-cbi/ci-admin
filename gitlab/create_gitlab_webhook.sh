#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2022 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Create webhook in GitLab

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'
SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../pass/pass_wrapper.sh"

GITLAB_PASS_DOMAIN="gitlab.eclipse.org"

help() {
  printf "Available commands:\n"
  printf "Command\t\tDescription\n\n"
  printf "repo\t\tCreate repo webhook.\n"
  printf "group\t\tCreate group webhook.\n"
  exit 0
}

_create_gitlab_webhook() {
  local project_name="${1:-}"
  local repo_group_name="${2:-}"
  local repo_group="${3:-}"
  local short_name="${project_name##*.}"
  local default_webhook_url="https://ci.eclipse.org/${short_name}/gitlab-webhook/post"
  local webhook_url="${4:-${default_webhook_url}}"

  # verify input
  if [ -z "${project_name}" ]; then
    printf "ERROR: a project name (e.g. 'technology.cbi' for CBI project) must be given.\n"
    exit 1
  fi
  if [ -z "${repo_group_name}" ]; then
    printf "ERROR: a %s name must be given.\n" "${repo_group}"
    exit 1
  fi

  local pw_store_path="bots/${project_name}/${GITLAB_PASS_DOMAIN}"

  if ! passw cbi "${pw_store_path}/webhook-secret" &> /dev/null ; then
    echo "Creating webhook secret credentials in password store..."
    pwgen -1 -s -r '&\!|%{'\''$' -y 24 | passw cbi insert --echo "${pw_store_path}/webhook-secret"
  else
    echo "Found ${GITLAB_PASS_DOMAIN} webhook-secret credentials for '${project_name}' in password store. Skipping creation..."
  fi
  webhook_secret="$(passw cbi "${pw_store_path}/webhook-secret")"

 "${SCRIPT_FOLDER}/gitlab_admin.sh" "create_${repo_group}_webhook" "${repo_group_name}" "${webhook_url}" "${webhook_secret}"
}

repo() {
  local project_name="${1:-}"
  local repo_name="${2:-}"
  _create_gitlab_webhook "${project_name}" "${repo_name}" "repo"
}

group() {
  local project_name="${1:-}"
  local group_name="${2:-}"
  _create_gitlab_webhook "${project_name}" "${group_name}" "group"
}

"$@"

# show help menu, if no first parameter is given
if [[ -z "${1:-}" ]]; then
  help
fi

