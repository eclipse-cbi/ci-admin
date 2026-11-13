#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2026 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# This tools requires the bw executable to be installed
# https://vault.bitwarden.com/download/?app=cli&platform=linux

# TODO:
# - check if bw tool is installed

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

#set -x

IFS=$'\n\t'

SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
CI_ADMIN_ROOT="${SCRIPT_FOLDER}/.."
BW_CLIENTID="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "bitwarden.client_id")"
BW_CLIENTSECRET="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "bitwarden.client_secret")"

export BW_CLIENTID BW_CLIENTSECRET

cleanup() {
  bw lock --quiet
  bw logout --quiet
}
trap cleanup EXIT

#login
bw login --apikey > /dev/null
response="$(bw unlock | grep 'export' | sed 's/\$ export BW_SESSION=//')"

BW_SESSION="${response}"
export BW_SESSION

#main
collection_id="${1:-}"
secret_name="${2:-}"

# check that collection_id is not empty
if [[ -z "${collection_id}" ]]; then
  printf "ERROR: a BitWarden collection ID must be given.\n"
  exit 1
fi

# check that secret name is not empty
if [[ -z "${secret_name}" ]]; then
  printf "ERROR: a secret name must be given.\n"
  exit 1
fi

# TODO: gracefully deal with more than one found secret
secret="$(bw list items --collectionid "${collection_id}" --search "${secret_name}")"

echo "${secret}" | jq -r '.'

