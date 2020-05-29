#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2020 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Add credentials (email, username, password)
# * Generate password
# * add credentials to password store


# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

source add_creds_common.sh

script_name="$(basename ${0})"
project_name="${1:-}"

site="${2:-}"
site_name="${site}"

usage() {
  printf "Usage: %s project_name site_name\n" "$script_name"
  printf "\t%-16s project name (e.g. technology.cbi for CBI project).\n" "project_name"
  printf "\t%-16s site name (e.g. docker.com).\n" "site_name"
}

# check that two parameters are given
if [ "$#" -ne 2 ]; then
  printf "ERROR: a project name and a site name must be given.\n"
  usage
  exit 1
fi

# check that project name is not empty
if [ "$project_name" == "" ]; then
  printf "ERROR: a project name must be given.\n"
  usage
  exit 1
fi

# check that project name contains a dot
if [[ "$project_name" != *.* ]]; then
  printf "ERROR: the full project name with a dot must be given (e.g. technology.cbi).\n"
  usage
  exit 1
fi

# check that site name is not empty
if [ "${site}" == "" ]; then
  printf "ERROR: a site (e.g. docker.com) name must be given.\n"
  exit 1
fi

short_name=${project_name##*.}
pw_store_path=cbi-pass/bots/${project_name}/${site}

echo -n "${site_name} email: "; read -r email
# check that email is not empty
if [ "${email}" == "" ]; then
  printf "ERROR: an email must be given.\n"
  exit 1
fi

echo -n "${site_name} username: "; read -r user
# check that site name is not empty
if [ "${user}" == "" ]; then
  printf "ERROR: a username must be given.\n"
  exit 1
fi

echo ""
show_info

# check if password already exists
if [[ ! $(pass ${pw_store_path} &> /dev/null) ]]; then
  create_pw
  if [ "${pw}" == "" ]; then
    printf "ERROR: a password must be given.\n"
    exit 1
  fi
else
  printf "WARNING: ${site_name} credentials for ${project_name} already exist. Skipping creation...\n"
fi

add_to_pw_store

#TODO: push changes