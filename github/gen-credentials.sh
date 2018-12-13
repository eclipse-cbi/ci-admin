#! /usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2018 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Generates Github credentials and adds it to pass

################### This section not specific to this program ###################
# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

# Need readlink
if ! command -v readlink > /dev/null; then
  >&2 echo "ERROR: this program requires 'readlink'"
  exit 1
fi

SCRIPT_FOLDER="$(dirname $(readlink -f "${0}"))"
SCRIPT_NAME="$(basename $(readlink -f "${0}"))"
########################### End of the generic section ##########################

. "${SCRIPT_FOLDER}/../pass/sanity-check.sh"

usage() {
  >&2 printf "Generates Github credentials and adds them to pass. Password is read from stdin"
  >&2 printf "Usage: %s project_name username email\n" "$SCRIPT_NAME"
  >&2 printf "\t%-16s Fully qualified project name (e.g. technology.cbi for CBI project).\n" "project_name"
  >&2 printf "\t%-16s Github username (optional) (e.g. cbi-bot for CBI project).\n" "username"
  >&2 printf "\t%-16s Email of the user (optional) (e.g. cbi-bot@eclipse.org for CBI project).\n" "email"
}

project_name="${1:-}"

if [[ -z "${project_name}" ]]; then
  >&2 printf "ERROR: a project name must be given.\n"
  usage
  exit 1
fi

username="${2:-eclipse-${project_name##*.}-bot}"
email="${3:-${project_name##*.}-bot@eclipse.org}"

if [[ -z "${username}" ]]; then
  >&2 printf "ERROR: a user name must be given.\n"
  usage
  exit 1
fi

if [[ -z "${email}" ]]; then
  >&2 printf "ERROR: an email must be given.\n"
  usage
  exit 1
fi

pw_store_path="bots/${project_name}/github.com"

if pass "${pw_store_path}/username" &> /dev/null || pass "${pw_store_path}/password" &> /dev/null || pass "${pw_store_path}/email" &> /dev/null ; then
  >&2 printf "ERROR: some credentials already exist in pass for '${pw_store_path}'.\n"
  >&2 pass "${pw_store_path}"
  exit 4
fi 

password=$(${SCRIPT_FOLDER}/../utils/read-secret.sh)
echo ${username} | pass insert -m ${pw_store_path}/username > /dev/null
echo ${email} | pass insert -m ${pw_store_path}/email > /dev/null
pass insert -m ${pw_store_path}/password <<< "${password}" > /dev/null

echo "Github credentials of project '${project_name}' has been sucessfuly generated and stored in pass"