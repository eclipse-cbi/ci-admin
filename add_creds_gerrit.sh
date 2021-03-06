#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2018 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Add Gerrit credentials
# * generate SSH keys
# * add SSH keys to password store
# * create Gerrit account

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

source add_creds_common.sh

script_name="$(basename "${0}")"
project_name=${1:-}
forge=${2:-eclipse}

site=git.eclipse.org
site_name=Gerrit

verify_inputs

short_name=${project_name##*.}
pw_store_path=cbi-pass/bots/${project_name}/${site}
temp_path=/tmp/${short_name}_id_rsa

email="${short_name}-bot@eclipse.org"
user="genie.${short_name}"

show_info

get_bot_name() {
  read -p "Enter bot name (without the trailing 'Bot', e.g. 'CBI' for 'CBI Bot'): " bot_name
  echo "${bot_name}"
}

create_gerrit_account() {
  return_value=$(curl -s "https://git.${forge}.org/r/accounts/${email}")
  if [[ ${return_value} == "Account '${email}' not found" ]]; then
    bot_name=$(get_bot_name)
    echo
    printf "Creating Gerrit bot account...\n"
    pass "${pw_store_path}/id_rsa.pub" | ssh -p 29418 git.${forge}.org gerrit create-account --full-name "'${bot_name} Bot'" --email "${email}" --ssh-key - "genie.${short_name}"
    # does not work with newer Gerrit versions. Is it even necessary anymore?
    #echo "INSERT INTO account_external_ids (account_id,email_address,external_id) SELECT account_id,\"${email}\",\"gerrit:${email}\" FROM accounts WHERE preferred_email=\"${email}\";" | ssh -p 29418 git.${forge}.org gerrit gsql
    printf "\nFlushing Gerrit caches..."
    ssh -p 29418 git.${forge}.org gerrit flush-caches
    printf "Done.\n"
  else
    printf "Gerrit bot account %s already exists. Skipping creation...\n" "${email}"
    #printf "Adding SSH public key...\n"
    #pass ${pw_store_path}/id_rsa.pub | ssh -p 29418 git.${forge}.org gerrit set-account --add-ssh-key - genie.${short_name}
    exit 1
  fi
}

if check_pw_does_not_exists; then
  generate_ssh_keys
fi
create_gerrit_account

echo "#### Please fix the mail field in the LDAP account manually on build (should be ${email})! ####"

#TODO: push changes