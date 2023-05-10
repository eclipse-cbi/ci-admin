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
CI_ADMIN_ROOT="${SCRIPT_FOLDER}/.."

JIRO_ROOT_FOLDER="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "jiro-root-dir")"
PROJECTS_BOTS_API_ROOT_FOLDER="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "projects-bots-api-root-dir")"
#shellcheck disable=SC1091
source "${CI_ADMIN_ROOT}/pass/pass_wrapper.sh"

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
echo "Old name: ${PROJECT_NAME}   =>   New name: ${NEW_PROJECT_NAME}"
echo

RENAME_LOG="rename_project_${PROJECT_NAME}_to_${NEW_PROJECT_NAME}.log"
> "${RENAME_LOG}"

# adapt pass credentials
fix_pass() {
  local password_store_dir
  password_store_dir="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "cbi-dir" "password-store")"
  local new_pass_project="bots/${NEW_PROJECT_NAME}"

  echo "# Updating pass credentials..."

  # move pass credentials
  # check if it's already moved
  if [[ -d "${password_store_dir}/${new_pass_project}" ]]; then
    echo " * [SKIP] New pass folder ${new_pass_project} already exists."
  else
    pushd "${password_store_dir}/bots/"
    git mv "${PROJECT_NAME}" "${NEW_PROJECT_NAME}"
    popd
    echo " * [FIXED] pass folder was moved to ${new_pass_project}."
  fi

  if [[ "${OLD_SHORT_NAME}" != "${NEW_SHORT_NAME}" ]]; then
    # Gerrit
    if [[ -d "${password_store_dir}/${new_pass_project}/git.eclipse.org" ]]; then
      if [[ "$(passw cbi "${new_pass_project}/git.eclipse.org/username")" == "genie.${NEW_SHORT_NAME}" ]]; then
        echo " * [SKIP] Gerrit username has been updated already."
      else
        echo "genie.${NEW_SHORT_NAME}" | passw cbi insert --echo "${new_pass_project}/git.eclipse.org/username" >> "${RENAME_LOG}"
        echo " * [FIXED] Gerrit username updated (=> \"genie.${NEW_SHORT_NAME}\")."
      fi
    fi

    # projects-storage.eclipse.org
    if [[ -d "${password_store_dir}/${new_pass_project}/projects-storage.eclipse.org" ]]; then
      if [[ "$(passw cbi "${new_pass_project}/projects-storage.eclipse.org/username")" == "genie.${NEW_SHORT_NAME}" ]]; then
        echo " * [SKIP] projects-storage username has been updated already."
      else
        echo "genie.${NEW_SHORT_NAME}" | passw cbi insert --echo "${new_pass_project}/projects-storage.eclipse.org/username" >> "${RENAME_LOG}"
        echo " * [FIXED] projects-storage username updated (=> \"genie.${NEW_SHORT_NAME}\")."
      fi
    fi

    # GitHub
    if [[ -d "${password_store_dir}/${new_pass_project}/github.com" ]]; then
      local new_github_bot_name="eclipse-${NEW_SHORT_NAME}-bot"
      local new_github_bot_email="${NEW_SHORT_NAME}-bot@eclipse.org"
      if [[ "$(passw cbi "${new_pass_project}/github.com/username")" == "${new_github_bot_name}" ]] &&
         [[ "$(passw cbi "${new_pass_project}/github.com/email")" == "${new_github_bot_email}" ]]; then
        echo " * [SKIP] GitHub username and email have been updated already."
      else
        echo "${new_github_bot_name}" | passw cbi insert --echo "${new_pass_project}/github.com/username" >> "${RENAME_LOG}"
        echo "${new_github_bot_email}" | passw cbi insert --echo "${new_pass_project}/github.com/email" >> "${RENAME_LOG}"
        echo " * [FIXED] GitHub username and email updated (=> \"${new_github_bot_name}\", \"${new_github_bot_email}\")."
      fi
    fi

    # GitLab
    if [[ -d "${password_store_dir}/${new_pass_project}/gitlab.eclipse.org" ]]; then
      local new_gitlab_bot_name="${NEW_SHORT_NAME}-bot"
      local new_gitlab_bot_email="${NEW_SHORT_NAME}-bot@eclipse.org"
      if [[ "$(passw cbi "${new_pass_project}/github.com/username")" == "${new_gitlab_bot_name}" ]] &&
         [[ "$(passw cbi "${new_pass_project}/github.com/email")" == "${new_gitlab_bot_email}" ]]; then
        echo " * [SKIP] GitLab username and email have been updated already."
      else
        echo "${new_gitlab_bot_name}" | passw cbi insert --echo "${new_pass_project}/gitlab.eclipse.org/username" >> "${RENAME_LOG}"
        echo "${new_gitlab_bot_email}" | passw cbi insert --echo "${new_pass_project}/gitlab.eclipse.org/email" >> "${RENAME_LOG}"
        echo " * [FIXED] GitLab username and email updated (=> \"${new_gitlab_bot_name}\", \"${new_gitlab_bot_email}\")."
      fi
    fi

#TODO more
#TODO: create list of changes for external services like GitHub
#TODO: automate renaming of accounts
    echo
    echo " * [TODO] Change accounts on websites (GitHub, GitLab, etc)"
    read -rsp $'   Once you are done, press any key to continue...\n' -n1
  else
    echo " * [SKIP] Project short name did not change, skipping renaming of usernames, etc in pass..."
  fi
}

question() {
  local message="${1:-}"
  local action="${2:-}"
  read -rp "Do you want to ${message}? (Y)es, (N)o, E(x)it: " yn
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

update_projects_bot_api() {
  printf "\n# Updating projects-bots-api...\n"

#TODO: check automatically
  echo "  Connected to cluster?"
  read -rp "  Press enter to continue or CTRL-C to stop the script"
  echo
#TODO: check automatically
  echo "  Pulled latest version of projects-bots-api?"
  read -rp "  Press enter to continue or CTRL-C to stop the script"

  sed -i "s/${PROJECT_NAME}/${NEW_PROJECT_NAME}/" "${PROJECTS_BOTS_API_ROOT_FOLDER}/src/main/jsonnet/extensions.jsonnet"
  echo "  * [FIXED] Updated project name in extensions.jsonnet file (if it exists)..."

  echo "  * Regenerating bot API DB..."
  "${PROJECTS_BOTS_API_ROOT_FOLDER}/regen_db.sh" &>> "${RENAME_LOG}"

  printf "\n\n"
#TODO: Show error if files are equal
  read -rsp $'  Once you are done with comparing the diff, press any key to continue...\n' -n1
  echo "  * Deploying bot API DB..."
  "${PROJECTS_BOTS_API_ROOT_FOLDER}/deploy_db.sh" &>> "${RENAME_LOG}"

  printf "\n * [TODO] Double check that bot account has been added to API (https://api.eclipse.org/bots)...\n"
  read -rsp $'Once you are done, press any key to continue...\n' -n1
}

fix_pass
echo
question "rename the JIPP" "rename_jipp"
question "update the projects bot API" "update_projects_bot_api"

echo
echo "# Manual steps:"
echo " * [TODO] commit changes to cbi-pass"
echo " * [TODO] commit changes to JIRO repo"

