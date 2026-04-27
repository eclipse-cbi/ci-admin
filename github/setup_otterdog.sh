#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2024 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html,
# or the MIT License which is available at https://opensource.org/licenses/MIT.
# SPDX-License-Identifier: EPL-2.0 OR MIT
#*******************************************************************************

# Bash strict-mode
set -o errexit
# set -o nounset
set -o pipefail

IFS=$'\n\t'
SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
CI_ADMIN_ROOT="${SCRIPT_FOLDER}/.."

if [[ -z "${OTTERDOG_CONFIG_ROOT}" ]]; then
  OTTERDOG_CONFIG_ROOT="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "otterdog-configs-root-dir")"
fi

echo "OTTERDOG_CONFIG_ROOT: ${OTTERDOG_CONFIG_ROOT}"

#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../utils/common.sh"

PROJECT_NAME="${1:-}"

# check that project name is not empty
if [[ -z "${PROJECT_NAME}" ]]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

SHORT_NAME="${PROJECT_NAME##*.}"
GH_ORG="${2:-eclipse-${SHORT_NAME}}"

echo "GH_ORG: ${GH_ORG}"

setup_gh_bot() {
  "${SCRIPT_FOLDER}/setup_github_bot.sh" "${PROJECT_NAME}"
}

make_bot_owner() {
  printf "\n# Make bot owner of the org...\n"
  printf "\n# TODO: Make bot owner of org manually...\n"
  read -rsp $'Once you are done, press any key to continue...\n' -n1
}

create_otterdog_token() {
  printf "\n# Create Otterdog token...\n"
  if _check_pw_does_not_exist "${PROJECT_NAME}" "github.com/otterdog-token"; then
    python "${SCRIPT_FOLDER}/playwright/gh_create_otterdog_token.py" "${PROJECT_NAME}"
  fi
}

test_weblogin() {
  printf "\n# Testing otterdog web-login...\n"
  otterdog web-login "${GH_ORG}"
  echo "Waiting for 30s until new 2FA token is ready..."
  sleep 30
  read -rsp $'Once you are done, press any key to continue...\n' -n1
}

prepare_otterdog() {
  #TODO: check if otterdog is installed
  printf "\n# Prepare Otterdog...\n"
  pushd "${OTTERDOG_CONFIG_ROOT}" > /dev/null
  echo "Updating otterdog config repo..."
  
  # Check for unstaged changes and stash if necessary
  if ! git diff-files --quiet; then
    echo "Unstaged changes detected. Stashing them..."
    git stash push -u -m "Auto-stash before setup_otterdog pull"
    STASHED=true
  else
    STASHED=false
  fi
  
  git pull
  
  # Reapply stashed changes if any
  if [[ "${STASHED}" == "true" ]]; then
    echo "Reapplying stashed changes..."
    git stash pop
  fi
  
  echo "Adding config to otterdog.json..."
  cat <<EOF
    {
      "name": "${PROJECT_NAME}",
      "github_id": "${GH_ORG}"
    },

    file://${OTTERDOG_CONFIG_ROOT}/otterdog.json
EOF
  printf "\n# TODO: Add config to otterdog.json manually...\n"
  read -rsp $'Once you are done, press any key to continue...\n' -n1
  
  # Ask if user wants to test web-login
  _question_action "test otterdog web-login" test_weblogin
  
  # Show the changes to be committed
  printf "\n# Changes to otterdog.json:\n"
  git --no-pager diff otterdog.json
  
  # Commit and push otterdog.json change
  printf "\n# Committing and pushing otterdog.json changes...\n"
  read -rp "Enter the issue URL (e.g., https://gitlab.eclipse.org/eclipsefdn/emo-team/emo/-/issues/1106): " ISSUE_URL
  git add otterdog.json
  git commit -m "feat: add project ${PROJECT_NAME}

Related to ${ISSUE_URL}"
  git push

  popd > /dev/null
}

otterdog_config() {
  printf "\n# Configure Otterdog...\n"
  pushd "${OTTERDOG_CONFIG_ROOT}" > /dev/null
  # Import existing resources
  otterdog import "${GH_ORG}" || true
  printf "\n# TODO: Cleanup manually...\n"
  read -rsp $'Once you are done, press any key to continue...\n' -n1
  # Create default resources
  otterdog apply "${GH_ORG}" || true
  printf "\n# TODO: Check possible issues and cleanup manually...\n"
  read -rsp $'Once you are done, press any key to continue...\n' -n1
  # Commit changes
  otterdog push-config "${GH_ORG}" -m "Initial import"
  popd > /dev/null
}

install_otterdog_gh_app() {
  # local otterdog_app_url="https://github.com/organizations/EclipseFdn/settings/apps/eclipse-otterdog/installations"
  # printf "\n# Install Otterdog app...\n"
  # echo "* Go to ${otterdog_app_url} (should open browser automatically)"
  # echo "* Select GitHub org and 'Install'"
  # _open_url "${otterdog_app_url}"
  # read -rsp $'Once you are done, press any key to continue...\n' -n1
  echo "* Installing GitHub app via CLI..."
  otterdog install-app -a eclipse-eca-validation ${GH_ORG}
  otterdog install-app -a eclipse-otterdog ${GH_ORG}
  otterdog install-app -a eclipse-foundation-sync ${GH_ORG}
}

issue_comment() {
  cat <<EOF

Post the following on the corresponding HelpDesk issue:
-------------------------------------------------------

:white_check_mark: Otterdog has been enabled for the ${GH_ORG} organization.

The following repo has been created: https://github.com/${GH_ORG}/.eclipsefdn

You can find the current configuration at https://github.com/${GH_ORG}/.eclipsefdn/blob/main/otterdog/${GH_ORG}.jsonnet

A dashboard UI of the configuration can also be accessed at https://${GH_ORG}.github.io/.eclipsefdn/ which also provides
a playground to test snippets before making a PR. When you want to suggest changes, fork the repo, make changes and create a PR.
A workflow will automatically run and show you the changes that will be applied and validate that the configuration is correctly formatted and composed.

The documentation of all supported settings can be found here: https://otterdog.readthedocs.io/en/latest/reference/resource-format/

A list of all Eclipse projects that have it also enabled can be accessed here: https://eclipsefdn.github.io/otterdog-configs/

You can also navigate to https://otterdog.eclipse.org/projects/${PROJECT_NAME} to get more insights for your project in a dashboard like view.

If you have any problems, let us know.
EOF
}

#### MAIN

# Check if bot user exists, if not, create
_question_action "Setup GitHub bot" setup_gh_bot

# Make bot user the owner of the GH org
make_bot_owner

# Create Otterdog PAT token for bot user
_question_action "Create otterdog token" create_otterdog_token

# Prepare otterdog
_question_action "configure otterdog configuration file: otterdog.json" prepare_otterdog

# Install Eclipse Otterdog GH app,
_question_action "install GitHub apps" install_otterdog_gh_app

# Set up otterdog
_question_action "configure otterdog GitHub Organization"  otterdog_config

# Comment on the ticket
issue_comment
