#!/usr/bin/env bash

#*******************************************************************************
# Copyright (c) 2020 Eclipse Foundation and others.
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

project_name="${1:-}"

# check that project name is not empty
if [[ -z "${project_name}" ]]; then
  printf "ERROR: a project name must be given (e.g. technology.cbi for CBI project).\n"
  exit 1
fi

short_name="${project_name##*.}"
tmp_gpg="/tmp/temp_gpg_test"
pw_store_path="cbi-pass/bots/${project_name}/gpg"

rm -rf "${tmp_gpg}"
mkdir -p "${tmp_gpg}"
chmod 700 "${tmp_gpg}"

echo "allow-loopback-pinentry" > "${tmp_gpg}/gpg-agent.conf"

passphrase="$(pass "${pw_store_path}/passphrase")"

# read mail address from pass if possible
ml_name="$(pass "${pw_store_path}/email")"
if [[ -z "${ml_name}" ]]; then
  printf "ERROR: %s/email not found. Trying %s-dev instead.\n" "${pw_store_path}" "${short_name}"
  ml_name="${short_name}-dev@eclipse.org"
fi

gpg_sb() {
  gpg --homedir ${tmp_gpg} "$@"
}

# import parent and sub keys
gpg_sb --batch --import <<< "$(pass "${pw_store_path}/secret-keys.asc")"
gpg_sb --batch --import <<< "$(pass "${pw_store_path}/secret-subkeys.asc")"

# find key id
key_id=$(gpg_sb --list-keys --with-colons "<${ml_name}>" | awk -F: '/^pub:/ { print $5 }')
printf "Found key: %s\n" "${key_id}"

expire_sub_key() {
  local key_no="$1"

  #works as well
#  printf "key ${key_no}\nexpire\n5y\nsave\n" | gpg_sb --batch --passphrase-fd 3 --pinentry-mode=loopback --command-fd 0 --edit-key "${key_id}" 3<<< "${passphrase}"

  gpg_sb --batch --passphrase-fd 3 --pinentry-mode=loopback --command-fd 0 --edit-key "${key_id}" 3<<< "${passphrase}" << EOF 
key ${key_no}
expire
5y
save
EOF
}

expire_sub_key "1"
expire_sub_key "2"

# export secret subkeys
gpg_sb --batch --passphrase-fd 3 --pinentry-mode=loopback --armor --export-secret-subkeys "${key_id}" 3<<< "${passphrase}" > secret-subkeys_new.asc

pass insert -m "${pw_store_path}/secret-subkeys.asc" < secret-subkeys_new.asc
rm -f secret-subkeys_new.asc

rm -rf "${tmp_gpg}"

echo "Done"
