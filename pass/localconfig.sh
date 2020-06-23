#! /usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2018 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Create a new SSH keypair in batch-mode and add it to pass

################### This section not specific to this program ###################
# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'
########################### End of the generic section ##########################

# Need pass
if ! command -v pass > /dev/null; then
  >&2 echo "ERROR: this program requires 'pass'"
  exit 1
fi

# Need readlink
if ! command -v readlink > /dev/null; then
  >&2 echo "ERROR: this program requires 'readlink'"
  exit 1
fi

LOCAL_CONFIG_FILE="${LOCAL_CONFIG_FILE:-"$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.localconfig"}"

if [[ ! -f "${LOCAL_CONFIG_FILE}" ]]; then
  echo "ERROR: File '$(readlink -f "${LOCAL_CONFIG_FILE}")' does not exists"
  echo "Create one to configure the location of the password store. Example:"
  echo '{"password-store": {"cbi-dir": "~/.password-store/cbi"}}'
  exit 1
fi
PASSWORD_STORE_DIR="$(jq -r '.["password-store"]["cbi-dir"]' "${LOCAL_CONFIG_FILE}")"
PASSWORD_STORE_DIR="$(readlink -f "${PASSWORD_STORE_DIR/#~\//${HOME}/}")"

if [[ ! -d "${PASSWORD_STORE_DIR}/bots" ]]; then
  echo "ERROR: Cannot find folder '${PASSWORD_STORE_DIR}/bots' which is expected from the CBI password store"
  exit 1
fi

export PASSWORD_STORE_DIR