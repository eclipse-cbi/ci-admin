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

# Sign with webmaster's key
"${SCRIPT_FOLDER}/../gpg/gpg_key_admin.sh" create_pgp_credentials "${PROJECT_NAME}"

# Add GPG passphrase
gpg_passphrase_secret_id="gpg-passphrase"
gpg_passphrase="$(passw cbi "${PASS_BASE_PATH}/passphrase")"


# add credentials to Jenkins instance
"${JIRO_ROOT_FOLDER}/jenkins-create-credentials.sh" "${PROJECT_NAME}"
"${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "default" "${PROJECT_NAME}" "${gpg_passphrase_secret_id}" "GPG Passphrase" "${gpg_passphrase}"

# extract secret-subkeys.asc file from pass
passw cbi "${PASS_BASE_PATH}/secret-subkeys.asc" > "${SECRET_SUBKEYS_FILENAME}"

# Add manually to JIPP
echo
echo "Add ${SECRET_SUBKEYS_FILENAME} to ${SHORT_NAME} JIPP manually..."
read -rsp "Press enter to continue or CTRL-C to stop the script"

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

