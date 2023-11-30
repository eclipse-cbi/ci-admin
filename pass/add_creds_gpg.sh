#!/bin/bash
#*******************************************************************************
# Copyright (c) 2018 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# This script creates a GPG key pair that can be used for deploying artifacts to Maven Central via Sonatype's OSSRH

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
SCRIPT_NAME="$(basename "${0}")"

#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../utils/common.sh"
#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/pass_wrapper.sh"

PROJECT_NAME="${1:-}"
DISPLAY_NAME="${2:-}"
FORGE="${3:-eclipse.org}"

usage() {
  printf "Usage: %s project_name displayname [forge]\n" "${SCRIPT_NAME}"
  printf "\t%-16s project name (e.g. technology.cbi for CBI project).\n" "project_name"
  printf "\t%-16s the full name of the project (e.g. 'Eclipse CBI Project' for CBI project).\n" "display_name"
  printf "\t%-16s the forge (optional) (default is 'eclipse.org').\n" "forge"
}

## Verify inputs

if [ "${PROJECT_NAME}" == "" ]; then
  printf "ERROR: a projectname must be given.\n"
  usage
  exit 1
fi

# check that project name contains a dot
if [[ "${PROJECT_NAME}" != *.* ]]; then
  printf "ATTENTION: the full project name does not contain a dot (e.g. technology.cbi). Please double-check that this is intentional!\n"
  read -p "Press enter to continue or CTRL-C to stop the script"
fi

if [ "${DISPLAY_NAME}" == "" ]; then
  printf "ERROR: a display name (e.g. 'Eclipse CBI Project' for CBI project) must be given.\n"
  usage
  exit 1
fi

if [ "${FORGE}" != "eclipse.org" ] && [ "${FORGE}" != "locationtech.org" ] && [ "${FORGE}" != "polarsys.org" ]; then
  printf "ERROR: forge must either be 'eclipse.org','locationtech.org' or 'polarsys.org'.\n"
  usage
  exit 1
fi

short_name="${PROJECT_NAME##*.}"
ML_NAME="${short_name}-dev"                # Mailing list name (e.g. cbi-dev)

TMP_GPG="/tmp/temp_gpg"
TMP_GPG_DOCKER="/run/gnupg"

gpg_sb() {
  docker run -i --rm -u "$(id -u)" -v "${TMP_GPG}:${TMP_GPG_DOCKER}" "eclipsecbi/gnupg:2.2.8-r0" "${@}"
}

generate_key() {
  local pass_phrase="${1:-}"
  local gen_key_config_file="gen_key_config"
  mkdir -p "${TMP_GPG}"
  chmod 700 "${TMP_GPG}"
  ## generate key config file
  cat <<EOF > ${TMP_GPG}/${gen_key_config_file}
%echo Generating keypair for ${DISPLAY_NAME} ...
Key-Type: RSA
Key-Length: 4096
Name-Real: ${DISPLAY_NAME}
Name-Email: ${ML_NAME}@${FORGE}
Expire-Date: 5y
# Strengthing hash-preferences
Preferences: SHA512 SHA384 SHA256 SHA224 AES256 AES192 AES CAST5 ZLIB BZIP2 ZIP Uncompressed
#ask-passphrase does not seem to work
#%ask-passphrase
Passphrase: ${pass_phrase}
# for testing
#%pubring ${ML_NAME}.pub
#%secring ${ML_NAME}.sec
%commit
%echo done
EOF

  printf "\nGenerating key non-interactively...\n\n"
  gpg_sb --batch --gen-key ${TMP_GPG_DOCKER}/${gen_key_config_file}

  printf "\nShredding config file...\n\n"
  shred -n 7 -u -z ${TMP_GPG}/${gen_key_config_file}

  printf "\nChecking keys...\n\n"
  gpg_sb --list-keys
}

generate_sub_keypair() {
  local key_id="${1:-}"
  local pass_phrase="${2:-}"
  printf "\nGenerating a signing (sub-)keypair...\n"
  local subkey_cmd
  subkey_cmd=$(cat <<EOM
addkey
4
4096
5y
${pass_phrase}
save
EOM
)

  gpg_sb --batch --command-fd 0 --pinentry-mode=loopback --expert --edit-key "${key_id}" <<< "${subkey_cmd}"
}

check_prefs() {
  local key_id="${1:-}"
  printf "\nChecking hash-preferences...\n\n"
  gpg_sb --batch --edit-key "${key_id}" showpref save exit
}

send_key() {
  local key_id="${1:-}"
  local keyserver="${2:-}"
  printf "\nSending key to keyserver...\n\n"
  gpg_sb --keyserver "${keyserver}" --send-keys "${key_id}"
}

export_keys(){
  local key_id="${1:-}"
  local pass_phrase="${2:-}"
  printf "\nExporting keys...\n\n"
  gpg_sb --batch --passphrase-fd 0 --pinentry-mode=loopback --armor --export "${key_id}" <<< "${pass_phrase}" > public-keys.asc
  gpg_sb --batch --passphrase-fd 0 --pinentry-mode=loopback --armor --export-secret-keys "${key_id}" <<< "${pass_phrase}" > secret-keys.asc
  gpg_sb --batch --passphrase-fd 0 --pinentry-mode=loopback --armor --export-secret-subkeys "${key_id}" <<< "${pass_phrase}" > secret-subkeys.asc
}

yes_skip_exit() {
  read -rp "Do you want to $1? (Y)es, (S)kip, E(x)it: " yn
  shift
  case $yn in
    [Yy]* ) "${@}";;
    [Ss]* ) echo "Skipping...";;
    [Xx]* ) exit;;
        * ) echo "Please answer (Y)es, (S)kip, E(x)it";;
  esac
}

add_to_pw_store() {
  local key_id="${1:-}"
  local pass_phrase="${2:-}"
  local pw_store_path="${3:-}"

  echo "${pass_phrase}" | passw cbi insert --echo "${pw_store_path}/passphrase"
  echo "${key_id}" | passw cbi insert --echo "${pw_store_path}/key_id"
  echo "${ML_NAME}@${FORGE}" | passw cbi insert --echo "${pw_store_path}/email"
  passw cbi insert -m "${pw_store_path}/public-keys.asc" < public-keys.asc
  passw cbi insert -m "${pw_store_path}/secret-keys.asc" < secret-keys.asc
  passw cbi insert -m "${pw_store_path}/secret-subkeys.asc" < secret-subkeys.asc
}

## Main
pass_phrase=$(_generate_shell_safe_password)
keyserver="keyserver.ubuntu.com"           # PGP keyserver
pw_store_path="bots/${PROJECT_NAME}/gpg"

yes_skip_exit "generate the main key" generate_key "${pass_phrase}"

key_id="$(gpg_sb --list-keys --with-colons "<${ML_NAME}@${FORGE}>" | awk -F: '/^pub:/ { print $5 }')"
printf "Found key: %s\n" "${key_id}"

check_prefs "${key_id}"

yes_skip_exit "generate a signing (sub-)keypair" generate_sub_keypair "${key_id}" "${pass_phrase}"

yes_skip_exit "export the keys" export_keys "${key_id}" "${pass_phrase}"

yes_skip_exit "add the keys, passphrase and metadata to the password store" add_to_pw_store "${key_id}" "${pass_phrase}" "${pw_store_path}"

yes_skip_exit "send the new key to the keyserver" send_key "${key_id}" "${keyserver}"

if [ -d ${TMP_GPG} ]; then
  printf "\nDeleting temporary keystore...\n\n"
  rm -rf "${TMP_GPG}"
fi

printf "Done.\n"
