#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2021 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

#TODO: use trap

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'
SCRIPT_FOLDER="$(dirname "$(readlink -f "${0}")")"

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

passw() {
  local store="${1:-}"
  if [ "${store}" != "cbi" ] && [ "${store}" != "it" ]; then
    printf "ERROR: only 'cbi' and 'it' are valid values.\n"
    exit 1
  fi
  # backup env variable
  local backup_pw_store_dir
  if [[ ! -z "${PASSWORD_STORE_DIR:-}" ]]; then
    backup_pw_store_dir="${PASSWORD_STORE_DIR}"
  fi

  local PASSWORD_STORE_DIR
  PASSWORD_STORE_DIR="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "${store}-dir" "password-store")"
  PASSWORD_STORE_DIR="$(readlink -f "${PASSWORD_STORE_DIR/#~\//${HOME}/}")"
  export PASSWORD_STORE_DIR

  local exitCode=0
  if ! pass "${@:2}"; then
    >&2 echo "ERROR: pass entry not found - " "${@:2}" "in store $store"
    exitCode=1
  fi

  # reset env variable
  if [[ ! -z "${backup_pw_store_dir:-}" ]]; then
    PASSWORD_STORE_DIR="${backup_pw_store_dir}"
    export PASSWORD_STORE_DIR
  else
    unset PASSWORD_STORE_DIR
  fi

  return ${exitCode}
}
