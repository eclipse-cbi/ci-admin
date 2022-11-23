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

PROJECT_NAME="${1:-}"
SHORT_NAME="${PROJECT_NAME##*.}"

# check that project name is not empty
if [[ -z "${PROJECT_NAME}" ]]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

JIRO_ROOT_FOLDER="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "jiro-root-dir")"

cleanup() {
  rm -rf "secret-subkeys.asc" "public-keys.asc" "secret-keys.asc"
}
trap cleanup EXIT

PASS_BASE_PATH="bots/${PROJECT_NAME}/gpg"
SECRET_SUBKEYS_FILENAME="secret-subkeys.asc"

# create pgp credentials
create_pgp_credentials() {
  local project_name="${1:-}"

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

  # add credentials to Jenkins instance
  "${JIRO_ROOT_FOLDER}/jenkins-create-credentials.sh" "${project_name}"


  # extract secret-subkeys.asc file from pass
  passw cbi "${PASS_BASE_PATH}/secret-subkeys.asc" > "${SECRET_SUBKEYS_FILENAME}"

  # Add manually to JIPP
  echo
  echo "Add ${SECRET_SUBKEYS_FILENAME} to ${SHORT_NAME} JIPP manually..."
  read -rsp "Press enter to continue or CTRL-C to stop the script"
  echo
}

create_pgp_credentials "${PROJECT_NAME}"

# Add GPG passphrase
gpg_passphrase_secret_id="gpg-passphrase"
gpg_passphrase="$(passw cbi "${PASS_BASE_PATH}/passphrase")"
"${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "default" "${PROJECT_NAME}" "${gpg_passphrase_secret_id}" "GPG Passphrase" "${gpg_passphrase}"

# Sign with webmaster's key
"${SCRIPT_FOLDER}/gpg_key_admin.sh" "sign" "${PROJECT_NAME}"

# Get public key ID
public_key_id="$(passw cbi "${PASS_BASE_PATH}/key_id")"

# Show helpdesk response template
printf "\n\n# Post instructions in HelpDesk ticket...\n"
cat <<EOF
The signing key on the ${SHORT_NAME} JIPP has been created.

Your public key is https://keyserver.ubuntu.com/pks/lookup?op=vindex&search=0x${public_key_id}

The key has been signed with the webmaster's key.

Jenkins credentials IDs are:
* ${SECRET_SUBKEYS_FILENAME}
* ${gpg_passphrase_secret_id}

EOF

