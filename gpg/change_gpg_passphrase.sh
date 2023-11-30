#!/usr/bin/env bash

#*******************************************************************************
# Copyright (c) 2022 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

SCRIPT_FOLDER="$(dirname "$(readlink -f "${0}")")"
#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../utils/common.sh"
#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../pass/pass_wrapper.sh"

TMP_GPG="/tmp/temp_gpg_test"

rm -rf "${TMP_GPG}"
mkdir -p "${TMP_GPG}"
chmod 700 "${TMP_GPG}"

_gpg_sb() {
  gpg --homedir "${TMP_GPG}" "$@"
}

_get_key_id() {
  local project_name="${1:-}"
  local short_name="${project_name##*.}"
  local pw_store_path="bots/${project_name}/gpg"

  # read mail address from pass if possible
  local ml_name
  ml_name="$(passw cbi "${pw_store_path}/email")"
  if [[ -z "${ml_name}" ]]; then
    printf "ERROR: %s/email not found. Trying %s-dev instead.\n" "${pw_store_path}" "${short_name}"
    ml_name="${short_name}-dev@eclipse.org"
  fi
  printf "\nml_name: %s\n" "${ml_name}" 1>&2

  # find key id
  local key_id
  key_id="$(_gpg_sb --list-keys --with-colons "<${ml_name}>" | awk -F: '/^pub:/ { print $5 }')"
  printf "Found key: %s\n\n" "${key_id}" 1>&2
  echo "${key_id}"
}

_preface() {
  # check that project name is not empty
  if [[ -z "${project_name}" ]]; then
    printf "ERROR: a project name must be given (e.g. technology.cbi for CBI project).\n"
    exit 1
  fi

  echo "allow-loopback-pinentry" > "${TMP_GPG}/gpg-agent.conf"

  local pw_store_path="bots/${project_name}/gpg"

  # import parent and sub keys
  _gpg_sb --batch --import <<< "$(passw cbi "${pw_store_path}/secret-keys.asc")"
  _gpg_sb --batch --import <<< "$(passw cbi "${pw_store_path}/secret-subkeys.asc")"

  # get passphrase from pass
  PASSPHRASE="$(passw cbi "${pw_store_path}/passphrase")"
}


project_name="${1:-}"
_preface "${project_name}"

pw_store_path="bots/${project_name}/gpg"

key_id="$(_get_key_id "${project_name}")"

echo "old passphrase: ${PASSPHRASE}"

generate_new_passphrase=$(_question_true_false "generate password")
if [ "$generate_new_passphrase" = false ]
then
  read -rp "Enter new passphrase: " NEW_PASSPHRASE
else
  NEW_PASSPHRASE=$(_generate_shell_safe_password)
  echo "new passphrase: ${NEW_PASSPHRASE}"
fi

# TODO automate
#_gpg_sb --edit-key "${key_id}"
_gpg_sb --change-passphrase "${key_id}"

# export changed keys
_gpg_sb --batch --passphrase-fd 3 --pinentry-mode=loopback --armor --export-secret-keys "${key_id}" 3<<< "${NEW_PASSPHRASE}" > "secret-keys.asc"
_gpg_sb --batch --passphrase-fd 3 --pinentry-mode=loopback --armor --export-secret-subkeys "${key_id}" 3<<< "${NEW_PASSPHRASE}" > "secret-subkeys.asc"

# add to pass
passw cbi insert -m "${pw_store_path}/secret-keys.asc" < "secret-keys.asc"
passw cbi insert -m "${pw_store_path}/secret-subkeys.asc" < "secret-subkeys.asc"

echo "${NEW_PASSPHRASE}" | passw cbi insert --echo "${pw_store_path}/passphrase"

rm -rf "secret-keys.asc"
rm -rf "secret-subkeys.asc"

echo "Done."

