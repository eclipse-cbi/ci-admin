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

#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../utils/common.sh"

# Create a GitHub token for the Renovate bot
# This token is used to authenticate the Renovate bot with GitHub
renovate() {
  local project_name="${1:-}"

  # check that project name is not empty
  if [[ -z "${project_name}" ]]; then
    printf "ERROR: a project name must be given.\n"
    exit 1
  fi
  
  printf "\n# Create renovate token...\n"
  if _check_pw_does_not_exist "${project_name}" "github.com/renovate-token"; then
    python "${SCRIPT_FOLDER}/playwright/gh_create_renovate_token.py" "${project_name}"
  fi

  printf "\n# TODO Create renovate token in otterdog...\n"
  cat <<EOF
    secrets: [
    	orgs.newRepoSecret('RENOVATE_TOKEN') {
      	value: "pass:bots/${project_name}/github.com/renovate-token",
    	},
    ],

EOF
}


"$@"