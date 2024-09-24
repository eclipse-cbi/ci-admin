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
set -o nounset
set -o pipefail

IFS=$'\n\t'
SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
CI_ADMIN_ROOT="${SCRIPT_FOLDER}/.."
OTTERDOG_CONFIGS_ROOT="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "otterdog-configs-root-dir")"

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

check_if_bot_exists() {
  printf "\n# Check if bot exists...\n"
  if _check_pw_does_not_exist "${PROJECT_NAME}" "github.com/username"; then
    #FIXME use setup_github_bot.sh script
    printf "\n# TODO: Create bot account (semi manually)...\n"
    read -rsp $'Once you are done, press any key to continue...\n' -n1
  fi
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

prepare_otterdog() {
  #TODO: check if otterdog is installed
  printf "\n# Prepare Otterdog...\n"
  pushd "${OTTERDOG_CONFIGS_ROOT}" > /dev/null
  # Add config to otterdog.json
  cat <<EOF
    {
      "name": "${PROJECT_NAME}",
      "github_id": "${GH_ORG}"
    },
EOF
  printf "\n# TODO: Add config to ottedog.json manually...\n"
  read -rsp $'Once you are done, press any key to continue...\n' -n1
  # Test login with otterdog webui
  otterdog web-login "${GH_ORG}"
  # Commit and push otterdog.json change
  printf "\n# TODO: Commit and push otterdog.json change manually...\n"
  echo "Waiting for 30s until new 2FA token is ready..."
  sleep 30
  read -rsp $'Once you are done, press any key to continue...\n' -n1
  popd > /dev/null
}

otterdog_config() {
  printf "\n# Configure Otterdog...\n"
  #TODO: check if next commands can be skipped
  pushd "${OTTERDOG_CONFIGS_ROOT}" > /dev/null
  # Import existing resources
  otterdog import "${GH_ORG}" || true
  # Create default resources
  otterdog apply "${GH_ORG}" || true
  printf "\n# TODO: Check possible issues and cleanup manually...\n"
  read -rsp $'Once you are done, press any key to continue...\n' -n1
  # Commit changes
  otterdog push-config "${GH_ORG}" -m "Initial import"
  popd > /dev/null
}

install_otterdog_gh_app() {
  local otterdog_app_url="https://github.com/organizations/EclipseFdn/settings/apps/eclipse-otterdog-app/installations"
  printf "\n# Install Otterdog app...\n"
  echo "* Go to ${otterdog_app_url} (should open browser automatically)"
  echo "* Select GitHub org and 'Install'"
  _open_url "${otterdog_app_url}"
  read -rsp $'Once you are done, press any key to continue...\n' -n1
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
That is often quite helpful to get ideas about how others do their configurations.

If you have any problems, let us know.
EOF
}

#### MAIN

# Check if bot user exists, if not, create
check_if_bot_exists

# Make bot user the owner of the GH org
make_bot_owner

# Create Otterdog PAT token for bot user
create_otterdog_token

# Prepare otterdog
prepare_otterdog

# Set up otterdog
otterdog_config

# Install Eclipse Otterdog GH app
install_otterdog_gh_app

# Comment on the ticket
issue_comment

