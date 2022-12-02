#!/usr/bin/env bash

#*******************************************************************************
# Copyright (c) 2022 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Setup GPG signing only (not for OSSRH/Maven Central)

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

SCRIPT_FOLDER="$(dirname "$(readlink -f "${0}")")"
#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../pass/pass_wrapper.sh"

cleanup() {
  rm -rf "secret-subkeys.asc" "public-keys.asc" "secret-keys.asc"
}
trap cleanup EXIT

help() {
  printf "Available commands:\n"
  printf "Command\t\tDescription\n\n"
  printf "create_pgp_credentials\t\tCreate gpg key for project.\n"
  exit 0
}

# create pgp credentials
create_pgp_credentials() {
  local project_name="${1:-}"
  # check that project name is not empty
  if [[ -z "${project_name}" ]]; then
    printf "ERROR: a project name must be given.\n"
    exit 1
  fi
  PASS_BASE_PATH="bots/${project_name}/gpg"

  # get display name from PMI API
  local display_name
  display_name="$(curl -sSL "https://projects.eclipse.org/api/projects/${project_name}.json" | jq -r .[].name)"
  if [[ -z "${display_name}" ]]; then
    printf "ERROR: display name for %s not found in PMI API.\n" "${project_name}"
    read -p "Press enter a display name for '${project_name}': " display_name
    if [[ -z "${display_name}" ]]; then
      exit 1
    fi
  else
    printf "Found display name: %s.\n" "${display_name}"
  fi

  if passw cbi "${PASS_BASE_PATH}/secret-subkeys.asc" &> /dev/null ; then
    printf "%s credentials for %s already exist. Skipping creation...\n" "${PASS_BASE_PATH}" "${project_name}"
  else
    "${SCRIPT_FOLDER}/../pass/add_creds_gpg.sh" "${project_name}" "${display_name}"
  fi
  
  # Sign with webmaster's key
  "${SCRIPT_FOLDER}/gpg_key_admin.sh" "sign" "${project_name}"
}


"$@"

# show help menu, if no first parameter is given
if [[ -z "${1:-}" ]]; then
  help
fi