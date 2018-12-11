#!/bin/bash
#*******************************************************************************
# Copyright (c) 2018 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Add GitHub credentials
# * Generate password (optional)
# * add credentials to password store


source add_creds_common.sh

script_name="$(basename ${0})"
project_name="$1"

site=github.com
site_name=GitHub

verify_inputs

short_name=${project_name##*.}
pw_store_path=cbi-pass/bots/${project_name}/${site}
temp_path=/tmp/${short_name}_id_rsa

email="${short_name}-bot@eclipse.org"
user="eclipse-${short_name}-bot"

check_pw_does_not_exists

show_info

create_pw

add_to_pw_store

#TODO: push changes