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
#set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

source add_creds_common.sh

script_name="$(basename ${0})"
project_name=${1:-}
path=${2:-}

# Need to be set, otherwise add_creds_common.sh complains about unset variables
site="foobar"
site_name="SSH"

verify_inputs

short_name=${project_name##*.}
pw_store_path=cbi-pass/bots/${project_name}/${path}
echo "pw_store_path: ${pw_store_path}";
temp_path=/tmp/${short_name}_id_rsa

email="${short_name}-bot@eclipse.org"
user="genie.${short_name}"


# check that the entries do not exist yet
# checks for id_rsa, so different than check_pass_no_exists
if [[ $(pass ${pw_store_path}/id_rsa &> /dev/null) ]]; then
  printf "ERROR: credentials for ${path} already exist in pass.\n"
  exit 1
fi

show_info

generate_ssh_keys
