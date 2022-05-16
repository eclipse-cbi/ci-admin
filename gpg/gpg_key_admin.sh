#!/usr/bin/env bash

#*******************************************************************************
# Copyright (c) 2021 Eclipse Foundation and others.
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

# TODO:
# help menu generated from function names

# PGP keyserver
#KEYSERVER="pgp.mit.edu"                      # unreliable!
KEYSERVER="keyserver.ubuntu.com"

TMP_GPG="/tmp/temp_gpg_test"
  
rm -rf "${TMP_GPG}"
mkdir -p "${TMP_GPG}"
chmod 700 "${TMP_GPG}"

_gpg_sb() {
  gpg --homedir "${TMP_GPG}" "$@"
}

_expire_sub_key() {
  local key_id="${1:-}"
  local key_no="${2:-}"

  #works as well
  #printf "key ${key_no}\nexpire\n5y\nsave\n" | _gpg_sb --batch --passphrase-fd 3 --pinentry-mode=loopback --command-fd 0 --edit-key "${key_id}" 3<<< "${PASSPHRASE}"

  _gpg_sb --batch --passphrase-fd 3 --pinentry-mode=loopback --command-fd 0 --edit-key "${key_id}" 3<<< "${PASSPHRASE}" << EOF 
key ${key_no}
expire
5y
save
EOF
}

_get_key_id() {
  local project_name="${1:-}"
  local short_name="${project_name##*.}"

  # read mail address from pass if possible
  local ml_name
  ml_name="$(pass "${PW_STORE_PATH}/email")"
  if [[ -z "${ml_name}" ]]; then
    printf "ERROR: %s/email not found. Trying %s-dev instead.\n" "${PW_STORE_PATH}" "${short_name}"
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

  PW_STORE_PATH="cbi-pass/bots/${project_name}/gpg"

  # import parent and sub keys
  _gpg_sb --batch --import <<< "$(pass "${PW_STORE_PATH}/secret-keys.asc")"
  _gpg_sb --batch --import <<< "$(pass "${PW_STORE_PATH}/secret-subkeys.asc")"

  # get passphrase from pass
  PASSPHRASE="$(pass "${PW_STORE_PATH}/passphrase")"
}

_upload_question() {
  read -p "Do you want to send the updated keys to a keyserver? (Y)es, (N)o, E(x)it: " yn
  case $yn in
    [Yy]* ) upload "${project_name}";;
    [Nn]* ) exit 0;;
    [Xx]* ) exit 0;;
        * ) echo "Please answer (Y)es, (N)o, E(x)it"; _upload_question;
  esac
}

help() {
  printf "Available commands:\n"
  printf "Command\t\tDescription\n\n"
  printf "renew\t\tRenew expiration and send key to key server.\n"
  printf "revoke\t\tRevoke public key on key server.\n"
  printf "sign\t\tSign key with webmaster key.\n"
  printf "test\t\tTest if passphrase works with GPG keys.\n"
  printf "upload\t\tUpload public key to key server.\n"
  exit 0
}

#### commands

renew() {
  local project_name="${1:-}"
  _preface "${project_name}"

  local key_id
  key_id="$(_get_key_id "${project_name}")"

  _gpg_sb --list-secret-keys --list-options show-unusable-subkeys

  _expire_sub_key "${key_id}" "1"
  _expire_sub_key "${key_id}" "2"

  mkdir -p "${project_name}"
  _gpg_sb --batch --passphrase-fd 3 --pinentry-mode=loopback --armor --export-secret-subkeys "${key_id}" 3<<< "${PASSPHRASE}" > "${project_name}/secret-subkeys.asc"

  pass insert -m "${PW_STORE_PATH}/secret-subkeys.asc" < "${project_name}/secret-subkeys.asc"

  echo
  _upload_question
  echo
  echo "TODO: Update secret-subkeys.asc Jenkins credential on JIPP (manually) from /ci-admin/gpg/${project_name}/secret-subkeys.asc"
  read -p "Press enter to continue or CTRL-C to stop the script"
  echo
  echo "Deleting ${project_name} directory..."
  rm -rf "${project_name}"
  echo
  echo "TODO: Push changes to cbi-pass repo."
  read -p "Press enter to continue or CTRL-C to stop the script"
}

revoke() {
  local project_name="${1:-}"
  _preface "${project_name}"

  local key_id
  key_id="$(_get_key_id "${project_name}")"

  local revoke_file="revoke.asc"

  _gpg_sb --list-keys

  _gpg_sb --output "${revoke_file}" --passphrase-fd 3 --pinentry-mode=loopback --gen-revoke "${key_id}" 3<<< "${PASSPHRASE}"
  _gpg_sb --import "${revoke_file}"

  _gpg_sb --keyserver "${KEYSERVER}" --search-keys "${key_id}"

  echo
  _upload_question
  
  rm -rf "${revoke_file}"
}

sign() {
  local project_name="${1:-}"

  # check that project name is not empty
  if [[ -z "${project_name}" ]]; then
    printf "ERROR: a project name must be given (e.g. technology.cbi for CBI project).\n"
    exit 1
  fi

  echo "allow-loopback-pinentry" > "${TMP_GPG}/gpg-agent.conf"
  # import webmaster's key
  local pw_store_path_wm="eclipse/IT/accounts/gpg/webmaster"
  _gpg_sb --import <<< "$(pass "${pw_store_path_wm}/secret-key.asc")"

  # import public key
  PW_STORE_PATH="cbi-pass/bots/${project_name}/gpg"
  _gpg_sb --batch --import <<< "$(pass "${PW_STORE_PATH}/public-keys.asc")"

  local key_id
  key_id="$(_get_key_id "${project_name}")"

  _gpg_sb --list-keys
  echo "Found key ${key_id}."
  _gpg_sb --sign-key "${key_id}"

  #TODO: use _upload_question
  upload "${project_name}"
}

test() {
  local project_name="${1:-}"
  _preface "${project_name}"

  local key_id
  key_id="$(_get_key_id "${project_name}")"

  # test passphrase from pass
  echo "1234" | _gpg_sb --batch --passphrase-fd 3 --pinentry-mode=loopback -o /dev/null --local-user "${key_id}" -as - 3<<< "${PASSPHRASE}" && echo "The passphrase stored in pass is correct!"
}

upload() {
  local project_name="${1:-}"
  _preface "${project_name}"

  local key_id
  key_id="$(_get_key_id "${project_name}")"

  printf "\nSending key to keyserver...\n\n"
  _gpg_sb --keyserver "${KEYSERVER}" --send-keys "${key_id}"
}

"$@"

#TODO: check that only the listed commands are used

# show help menu, if no first parameter is given
if [[ -z "${1:-}" ]]; then
  help
fi

rm -rf "${TMP_GPG}"
echo "Done"

