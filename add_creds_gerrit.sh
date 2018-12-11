#!/bin/bash
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

source add_creds_common.sh

script_name="$(basename ${0})"
project_name="$1"

site=git.eclipse.org
site_name=Gerrit

verify_inputs

short_name=${project_name##*.}
pw_store_path=cbi-pass/bots/${project_name}/${site}
temp_path=/tmp/${short_name}_id_rsa

email="${short_name}-bot@eclipse.org"
user="eclipse-${short_name}-bot"

check_pw_does_not_exists

show_info

create_gerrit_account() {
  #TODO: check if account already exists
  printf "Creating Gerrit bot account..."
  pass ${pw_store_path}/id_rsa.pub | ssh -p 29418 git.eclipse.org gerrit create-account --full-name "'${short_name} Bot'" --email "${email}" --ssh-key - genie.${short_name}
  echo "INSERT INTO account_external_ids (account_id,email_address,external_id) SELECT account_id,\"${email}\",\"gerrit:${email}\" FROM accounts WHERE preferred_email=\"${email}\";" | ssh -p 29418 git.eclipse.org gerrit gsql
  ssh -p 29418 git.eclipse.org gerrit flush-caches
  printf "Done.\n"
}

generate_ssh_keys
create_gerrit_account

#TODO: push changes