#!/usr/bin/env bash

#*******************************************************************************
# Copyright (c) 2022 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Rename a project

#TODO: write verbose output to log file and be less verbose by default

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'
SCRIPT_FOLDER="$(dirname "$(readlink -f "${0}")")"

JIRO_ROOT_FOLDER="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "jiro-root-dir")"
#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../pass/pass_wrapper.sh"

PROJECT_NAME="${1:-}"
NEW_PROJECT_NAME="${2:-}"
OLD_SHORT_NAME="${PROJECT_NAME##*.}"
NEW_SHORT_NAME="${NEW_PROJECT_NAME##*.}"

if [[ -z "${PROJECT_NAME}" ]]; then
  >&2 printf "ERROR: a project name must be given.\n"
  exit 1
fi

if [[ -z "${NEW_PROJECT_NAME}" ]]; then
  >&2 printf "ERROR: a new project name must be given.\n"
  exit 1
fi

echo
echo "Old name: ${PROJECT_NAME}   =>   ${NEW_PROJECT_NAME}"
echo

# adapt pass credentials
fix_pass() {
  local password_store_dir
  password_store_dir="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "cbi-dir" "password-store")"
  local new_pass_project="bots/${NEW_PROJECT_NAME}"

  # move pass credentials
  # check if it's already moved
  if [[ -d "${password_store_dir}/${new_pass_project}" ]]; then
    echo "${password_store_dir}/${new_pass_project} already exists, skipping..."
  else
    pushd "${password_store_dir}/bots/"
    git mv "${PROJECT_NAME}" "${NEW_PROJECT_NAME}"
    popd
  fi

  if [[ "${OLD_SHORT_NAME}" != "${NEW_SHORT_NAME}" ]]; then
    # Gerrit
    if [[ -d "${password_store_dir}/${new_pass_project}/git.eclipse.org" ]]; then
      echo "Updating Gerrit username (=> \"genie.${NEW_SHORT_NAME}\")..."
      echo "genie.${NEW_SHORT_NAME}" | passw cbi insert --echo "${new_pass_project}/git.eclipse.org/username"
    fi

    # projects-storage.eclipse.org
    if [[ -d "${password_store_dir}/${new_pass_project}/projects-storage.eclipse.org" ]]; then
      echo "Updating projects-storage username (=> \"genie.${NEW_SHORT_NAME}\")..."
      echo "genie.${NEW_SHORT_NAME}" | passw cbi insert --echo "${new_pass_project}/projects-storage.eclipse.org/username"
    fi

    # GitHub
    if [[ -d "${password_store_dir}/${new_pass_project}/github.com" ]]; then
      echo "Updating GitHub username and email (=> \"eclipse-${NEW_SHORT_NAME}-bot\", \"${NEW_SHORT_NAME}-bot@eclipse.org\")..."
      echo "eclipse-${NEW_SHORT_NAME}-bot" | passw cbi insert --echo "${new_pass_project}/github.com/username"
      echo "${NEW_SHORT_NAME}-bot@eclipse.org" | passw cbi insert --echo "${new_pass_project}/github.com/email"
    fi

    # GitLab
    if [[ -d "${password_store_dir}/${new_pass_project}/gitlab.eclipse.org" ]]; then
      echo "Updating GitLab username and email (=> \"${NEW_SHORT_NAME}-bot\", \"${NEW_SHORT_NAME}-bot@eclipse.org\")..."
      echo "${NEW_SHORT_NAME}-bot" | passw cbi insert --echo "${new_pass_project}/gitlab.eclipse.org/username"
      echo "${NEW_SHORT_NAME}-bot@eclipse.org" | passw cbi insert --echo "${new_pass_project}/gitlab.eclipse.org/email"
    fi

#TODO more
#TODO: create list of changes for external services like GitHub
#TODO: automate renaming of accounts
    echo "TODO: change accounts on websites (GitHub, GitLab, etc)"
    read -rsp $'Once you are done, press any key to continue...\n' -n1
  else
    echo "Project short name did not change, skipping renaming of usernames, etc in pass..."
  fi
}

question() {
  local message="${1:-}"
  local action="${2:-}"
  read -p "Do you want to ${message}? (Y)es, (N)o, E(x)it: " yn
  case $yn in
    [Yy]* ) ${action};;
    [Nn]* ) return ;;
    [Xx]* ) exit 0;;
        * ) echo "Please answer (Y)es, (N)o, E(x)it"; question "${message}" "${action}";
  esac
}

rename_jipp() {
  # call script in jiro folder to do the renaming in jiro
  "${JIRO_ROOT_FOLDER}/incubation/rename_jipp.sh" "${PROJECT_NAME}" "${NEW_PROJECT_NAME}"
}

fix_pass
question "rename the JIPP" "rename_jipp"

echo
echo "TODO:"
echo " * commit changes to cbi-pass"
echo " * commit changes to JIRO repo"

