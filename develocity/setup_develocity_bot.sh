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
SCRIPT_FOLDER="$(dirname "$(readlink -f "${0}")")"
CI_ADMIN_ROOT="${SCRIPT_FOLDER}/.."

#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../utils/common.sh"

PROJECT_NAME="${1:-}"
SHORT_NAME="${PROJECT_NAME##*.}"

export DEVELOCITY_ENV="staging"
[[ -n "$DEVELOCITY_ENV" ]] && DEVELOCITY_ENV="-${DEVELOCITY_ENV}"

DEVELOCITY_URL="${DEVELOCITY_URL:-"https://develocity${DEVELOCITY_ENV}.eclipse.org"}"

# check that project name is not empty
if [[ -z "${PROJECT_NAME}" ]]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

create_develocity_credentials() {
  echo "# Creating Develocity bot user credentials..."
  "${CI_ADMIN_ROOT}/pass/add_creds.sh" "develocity" "${PROJECT_NAME}" || true
}

set_up_develocity_account() {
  cat <<EOF

# Setting up Develocity bot account...
==================================
* Set up Develocity Hub bot account (${DEVELOCITY_URL}/admin/access/users/register)
  * Username: $(passw cbi "bots/${PROJECT_NAME}/develocity.eclipse.org/username")
  * Email: $(passw cbi "bots/${PROJECT_NAME}/develocity.eclipse.org/email")
  * First Name: bot
  * Last Name: ${SHORT_NAME}
  * Password: pass "bots/${PROJECT_NAME}/develocity.eclipse.org/password"
  * Require user to change password on first login: No
  * Roles: CI Agent
==================================

EOF
  _open_url "${DEVELOCITY_URL}/admin/access/users/register"
  read -rsp $'Once you are done, press any key to continue...\n' -n1
}

#### MAIN

create_develocity_credentials

set_up_develocity_account

printf "\n\n# TODO: Commit changes to pass...\n"
read -rsp $'Once you are done, press any key to continue...\n' -n1

