#!/bin/bash
#*******************************************************************************
# Copyright (c) 2018 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# This script creates a GPG key pair that can be used for deploying artifacts to Maven Central via Sonatype's OSSRH






script_name="$(basename ${0})"
project_name="$1"
display_name="$2"
forge=${3:-eclipse.org}

site=gpg
site_name=GPG

usage() {
  printf "Usage: %s project_name displayname [forge]\n" "${script_name}"
  printf "\t%-16s project name (e.g. technology.cbi for CBI project).\n" "project_name"
  printf "\t%-16s the full name of the project (e.g. 'Eclipse CBI Project' for CBI project).\n" "display_name"
  printf "\t%-16s the forge (optional) (default is 'eclipse.org').\n" "forge"
}

## Verify inputs

if [ "${project_name}" == "" ]; then
  printf "ERROR: a projectname must be given.\n"
  usage
  exit 1
fi

# check that project name contains a dot
if [[ "$project_name" != *.* ]]; then
  printf "ERROR: the full project name with a dot must be given (e.g. technology.cbi).\n"
  usage
  exit 1
fi

if [ "${display_name}" == "" ]; then
  printf "ERROR: a display name (e.g. 'Eclipse CBI Project' for CBI project) must be given.\n"
  usage
  exit 1
fi

if [ "${forge}" != "eclipse.org" ] && [ "${forge}" != "locationtech.org" ] && [ "${forge}" != "polarsys.org" ]; then
  printf "ERROR: forge must either be 'eclipse.org','locationtech.org' or 'polarsys.org'.\n"
  usage
  exit 1
fi


short_name=${project_name##*.}
pw_store_path=cbi-pass/bots/${project_name}/${site}

ml_name="${short_name}-dev"     # Mailing list name (e.g. cbi-dev)

keyserver=pool.sks-keyservers.net           # PGP keyserver

file_name=$ml_name@$forge.txt   # Passphrases file

tmp_gpg=/tmp/temp_gpg
tmp_gpg_docker=/run/gnupg
gen_key_config_file=gen_key_config


pw_gen() {
  # If pwgen is not installed, use /dev/urandom instead
  if hash pwgen 2>/dev/null; then
    pwgen -1 -s -y $1
  else
    </dev/urandom tr -dc 'A-Za-z0-9!"#$%&'\''()*+,-./:;<=>?@[\]^_`{|}~' | head -c $1
  fi
}

gpg_sb() {
  docker run -i --rm -u $(id -u) -v ${tmp_gpg}:${tmp_gpg_docker} eclipsecbi/gnupg:2.2.8-r0 $@
}

pass_phrase=$(pw_gen 64)

generate_key() {
  mkdir -p ${tmp_gpg}
  chmod 700 ${tmp_gpg}
  ## generate key config file
  cat <<EOF > ${tmp_gpg}/$gen_key_config_file
%echo Generating keypair for ${display_name} ...
Key-Type: RSA
Key-Length: 4096
Name-Real: ${display_name}
Name-Email: ${ml_name}@${forge}
Expire-Date: 5y
# Strengthing hash-preferences
Preferences: SHA512 SHA384 SHA256 SHA224 AES256 AES192 AES CAST5 ZLIB BZIP2 ZIP Uncompressed
#ask-passphrase does not seem to work
#%ask-passphrase
Passphrase: ${pass_phrase}
# for testing
#%pubring $ml_name.pub
#%secring $ml_name.sec
%commit
%echo done
EOF

  printf "\nGenerating key non-interactively...\n\n"
  gpg_sb --batch --gen-key ${tmp_gpg_docker}/$gen_key_config_file

  printf "\nShredding config file...\n\n"
  shred -n 7 -u -z ${tmp_gpg}/$gen_key_config_file

  printf "\nChecking keys...\n\n"
  gpg_sb --list-keys
}

generate_sub_keypair() {
  printf "\nGenerating a signing (sub-)keypair...\n"
  subkey_cmd=$(cat <<EOM
addkey
4
4096
5y
${pass_phrase}
save
EOM
)

  gpg_sb --batch --command-fd 0 --pinentry-mode=loopback --expert --edit-key $key_id <<< "${subkey_cmd}"
}

check_prefs() {
  printf "\nChecking hash-preferences...\n\n"
  gpg_sb --batch --edit-key $key_id showpref save exit
}

send_key() {
  printf "\nSending key to keyserver...\n\n"
  gpg_sb --keyserver $keyserver --send-keys $key_id
}

export_secret_subkey(){
  printf "\nExporting the secret part of the subkeys...\n\n"
  gpg_sb --batch --passphrase-fd 0 --pinentry-mode=loopback --armor --export-secret-subkeys $key_id <<< "${pass_phrase}" > secret-subkeys.asc
}

yes_skip_exit() {
  read -p "Do you want to $1? (Y)es, (S)kip, E(x)it: " yn
  case $yn in
    [Yy]* ) $2;;
    [Ss]* ) echo "Skipping...";;
    [Xx]* ) exit;;
        * ) echo "Please answer (Y)es, (S)kip, E(x)it";;
  esac
}

add_to_pw_store() {
  echo ${pass_phrase} | pass insert --echo ${pw_store_path}/passphrase
  cat secret-subkeys.asc | pass insert -m ${pw_store_path}/secret-subkeys.asc
}

## Main
yes_skip_exit "generate the main key" generate_key

key_id=$(gpg_sb --list-keys --with-colons "<${ml_name}@${forge}>" | awk -F: '/^pub:/ { print $5 }')
printf "Found key: %s\n" ${key_id}

check_prefs

yes_skip_exit "generate a signing (sub-)keypair" generate_sub_keypair

yes_skip_exit "send the new key to the keyserver" send_key

yes_skip_exit "export the secret part of the subkeys" export_secret_subkey

yes_skip_exit "add the keys and passphrase to the password store" add_to_pw_store


if [ -d ${tmp_gpg} ]; then
  printf "\nDeleting temporary keystore...\n\n"
  rm -rf ${tmp_gpg}
fi

printf "Done.\n"
