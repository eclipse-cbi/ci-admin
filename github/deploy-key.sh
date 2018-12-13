#! /usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2018 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Deploy a ssh key from pass to github 

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

# Need jq
if ! command -v readlink > /dev/null; then
  >&2 echo "ERROR: this program requires 'jq'"
  exit 1
fi

SCRIPT_FOLDER="$(dirname $(readlink -f "${0}"))"
SCRIPT_NAME="$(basename $(readlink -f "${0}"))"
########################### End of the generic section ##########################

. "${SCRIPT_FOLDER}/../pass/sanity-check.sh"

usage() {
  >&2 printf "Deploy a ssh key from pass to github"
  >&2 printf "Usage: %s project_name\n" "$SCRIPT_NAME"
  >&2 printf "\t%-16s Fully qualified project name (e.g. technology.cbi for CBI project).\n" "project_name"
}

project_name="${1:-}"

if [[ -z "${project_name}" ]]; then
  >&2 printf "ERROR: a project name must be given.\n"
  usage
  exit 1
fi

pw_store_path="bots/${project_name}/github.com"

# check github credentials exist
if ! pass "${pw_store_path}/username" > /dev/null || ! pass "${pw_store_path}/password" > /dev/null || ! pass "${pw_store_path}/email" > /dev/null; then
  >&2 echo "ERROR: there is no github credentials in pass for project '${project_name}'"
  >&2 pass "${pw_store_path}"
  exit 1
fi

# check github ssh key exist
if ! pass "${pw_store_path}/id_rsa.pub" > /dev/null || ! pass "${pw_store_path}/id_rsa" > /dev/null || ! pass "${pw_store_path}/id_rsa.passphrase" > /dev/null; then
  >&2 echo "ERROR: there is no github ssh key in pass for project '${project_name}'"
  >&2 pass "${pw_store_path}"
  exit 1
fi

credentials="-u "$(pass "${pw_store_path}/username"):$(pass "${pw_store_path}/password")""

response="$(mktemp)"

# get existing user pub keys
response_code="$(curl -K- https://api.github.com/user/keys -o "${response}" -s -w "%{http_code}" <<< ${credentials})"
if [[ $response_code -ne 200 ]]; then
  >&2 printf "ERROR: while getting list of ssh public key for project ${project_name} (username=$(pass "${pw_store_path}/username")).\n"
  >&2 cat "${response}"
  rm "${response}"
  exit 1
fi

# check if one matches with ${pw_store_path}/id_rsa.pub
if [[ $(jq -r "[ .[] | select(.key == (\"$(pass ${pw_store_path}/id_rsa.pub)\"|sub(\"[[:space:]]+$\"; \"\"))) ]|length" $response) -ne 0 ]]; then
  >&2 echo "ERROR: ssh public key for project ${project_name} is already deployed to github"
  >&2 jq ".[] | select(.key == (\"$(pass ${pw_store_path}/id_rsa.pub)\"|sub(\"[[:space:]]+$\"; \"\")))" $response
  rm "${response}"
  exit 2
fi

# add ${pw_store_path}/id_rsa.pub to github
request=$(cat <<EOM
{
  "title": "$(pass ${pw_store_path}/email)", 
  "key": "$(pass ${pw_store_path}/id_rsa.pub)"
}
EOM
)
response_code="$(curl -K- -X POST -H "Content-Type: application/json" -d "${request}" https://api.github.com/user/keys -o "${response}" -s -w "%{http_code}" <<< ${credentials})"
if [[ $response_code -ne 201 ]]; then
  >&2 printf "ERROR: while adding ssh public key for project ${project_name} (username=$(pass "${pw_store_path}/username")). Response code is not 201.\n"
  >&2 cat "${response}"
  rm "${response}"
  exit 1
fi

rm "${response}"
echo "SSH public key of project '${project_name}' has been sucessfuly deployed to github.com"