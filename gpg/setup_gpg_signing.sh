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

PROJECT_NAME="${1:-}"
SHORT_NAME="${PROJECT_NAME##*.}"

# check that project name is not empty
if [[ -z "${PROJECT_NAME}" ]]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

# get display name from PMI API
DISPLAY_NAME="$(curl -sSL "https://projects.eclipse.org/api/projects/${PROJECT_NAME}.json" | jq -r .[].name)"
if [[ -z "${DISPLAY_NAME}" ]]; then
  printf "ERROR: display name for %s not found in PMI API.\n" "${PROJECT_NAME}"
  exit 1
else
  printf "Found display name: %s.\n" "${DISPLAY_NAME}"
fi

JIRO_ROOT_FOLDER="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "jiro-root-dir")"

cleanup() {
  rm -rf "secret-subkeys.asc" "public-keys.asc" "secret-keys.asc"
}
trap cleanup EXIT

pass_base_path="cbi-pass/bots/${PROJECT_NAME}/gpg"
secret_subkeys_filename="secret-subkeys.asc"

# create pgp credentials
if pass "${pass_base_path}/secret-subkeys.asc" &> /dev/null ; then
  printf "%s credentials for %s already exist. Skipping creation...\n" "${pass_base_path}" "${PROJECT_NAME}"
else
  "${SCRIPT_FOLDER}/../pass/add_creds_gpg.sh" "${PROJECT_NAME}" "${DISPLAY_NAME}"
fi

# add credentials to Jenkins instance
"${JIRO_ROOT_FOLDER}/jenkins-create-credentials.sh" "${PROJECT_NAME}"


# extract secret-subkeys.asc file from pass
pass "${pass_base_path}/secret-subkeys.asc" > "${secret_subkeys_filename}"

# Add manually to JIPP
echo
echo "Add ${secret_subkeys_filename} to ${SHORT_NAME} JIPP manually..."
read -rsp "Press enter to continue or CTRL-C to stop the script"
echo

# Add GPG passphrase
gpg_passphrase_secret_id="gpg-passphrase"
gpg_passphrase="$(pass "${pass_base_path}/passphrase")"
"${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "default" "${PROJECT_NAME}" "${gpg_passphrase_secret_id}" "GPG Passphrase" "${gpg_passphrase}"

# Sign with webmaster's key
"${SCRIPT_FOLDER}/gpg_key_admin.sh" "sign" "${PROJECT_NAME}"

# Get public key ID
public_key_id="$(pass "${pass_base_path}/key_id")"

# Show helpdesk response template
printf "\n\n# Post instructions in HelpDesk ticket...\n"
cat <<EOF
The signing key on the ${SHORT_NAME} JIPP has been created.

Your public key is https://keyserver.ubuntu.com/pks/lookup?op=vindex&search=0x${public_key_id}

The key has been signed with the webmaster's key.

Jenkins credentials IDs are:
* ${secret_subkeys_filename}
* ${gpg_passphrase_secret_id}

EOF

