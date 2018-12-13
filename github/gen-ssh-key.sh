#! /usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2018 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Generates a new SSH keypair for github in batch-mode and adds it to pass

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

usage() {
  >&2 printf "Generate a new SSH key for github.com and add it to pass. Passphrase is read from stdin"
  >&2 printf "Usage: %s project_name\n" "$SCRIPT_NAME"
  >&2 printf "\t%-16s project name (e.g. technology.cbi for CBI project).\n" "project_name"
}

project_name="${1:-}"

if [[ -z "${project_name}" ]]; then
  >&2 printf "ERROR: a project name must be given.\n"
  usage
  exit 1
fi

pw_store_path="bots/${project_name}/github.com"

# generate and store ssh key
passphrase=$(${SCRIPT_FOLDER}/../utils/read-secret.sh)
${SCRIPT_FOLDER}/../pass/gen-ssh-key.sh "${pw_store_path}" <<< "${passphrase}"
echo "SSH public key of project '${project_name}' has been sucessfuly generated and stored in pass"