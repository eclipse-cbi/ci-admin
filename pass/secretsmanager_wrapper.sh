#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2024 Eclipse Foundation and others.
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
set +u
IFS=$'\n\t'

SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# 
# Login to the Secretsmanager using the 'vault' command using env variables or local cbi config file
# 
sm_login() { 

  if ! command -v vault > /dev/null; then
    >&2 echo "ERROR: this program requires 'vault' Client, see https://developer.hashicorp.com/vault/install"
    exit 1
  fi

  connected() {
    echo -e "You are connected to the Secretsmanager: ${VAULT_ADDR} "
    vault token lookup
    # vault token revoke -self # for testing
  }
  # Check if user is already authenticated
  [ "$(vault token lookup &>/dev/null)" ] && connected && return 0

  # test VAULT_ADDR  
  if [ -z "${VAULT_ADDR}" ]; then
    VAULT_ADDR="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "url" "secretsmanager")" || true
    if [ -z "$VAULT_ADDR" ]; then
      echo "ERROR: VAULT_ADDR is not set. Please set it in your environment \"export VAULT_ADDR="https://..."\" or in the local cbi config file: ~/.cbi/config."
      exit 1
    fi
    export VAULT_ADDR
  fi

  [ "$(vault token lookup &>/dev/null)" ] && connected && return 0

  # test VAULT_TOKEN
  echo "INFO: Start Auth with VAULT_TOKEN"
  vault_token() {
    VAULT_TOKEN="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "token" "secretsmanager")" || true
    if [ -z "$VAULT_TOKEN" ]; then
      echo "WARN: VAULT_TOKEN is not set. Please set it in your environment \"export VAULT_TOKEN="..."\" or in the local cbi config file: ~/.cbi/config."
    else
      export VAULT_TOKEN
    fi
  }
  validate_vault_token() { 
    if vault token lookup &>/dev/null; then
      connected && return 0
    else
      echo "WARN: VAULT_TOKEN is not valid $1. Please set it in your environment \"export VAULT_TOKEN=\"...\"\" or in the local cbi config file: ~/.cbi/config."
      unset VAULT_TOKEN
    fi
  }
  if [ -z "${VAULT_TOKEN}" ]; then
    vault_token
    validate_vault_token "from config file"
  else
    validate_vault_token "from env"
    vault_token
    validate_vault_token "from config file"
  fi
  # test login/password
  echo "INFO: Start Auth with login/password"
  echo "WARN: login/password are optional, prefer using a token"
  VAULT_PASSWORD="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "password" "secretsmanager")" || true
  if [ -z "$VAULT_PASSWORD" ]; then
    echo "WARN: VAULT_PASSWORD is not set. Please set it in your environment or in the local cbi config file: ~/.cbi/config."
  fi
  VAULT_LOGIN="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "login" "secretsmanager")" || true
  if [ -z "$VAULT_LOGIN" ]; then
    echo "WARN: VAULT_LOGIN is not set. Please set it in your environment or in the local cbi config file: ~/.cbi/config."
  fi
  if [ -z "${VAULT_LOGIN}" ]; then
    read -r -p "Username: " VAULT_LOGIN
    vault login -method=ldap username="${VAULT_LOGIN}"
  elif [ -z "${VAULT_PASSWORD}" ]; then
    vault login -method=ldap username="${VAULT_LOGIN}"
  else
    echo -n "${VAULT_PASSWORD}" | vault login -method=ldap username="${VAULT_LOGIN}" password=-
  fi

  [ ! "$(vault token lookup)" ] && echo "ERROR: Unable to login to the Secretsmanager" && exit 1

  VAULT_TOKEN=$(vault token lookup -format=json | jq -r '.data.id')
  export VAULT_TOKEN
  connected
  return 0
}

sm_login

# 
# Usage: sm_read <mount> <path>
# NOTE: path is the full path to the secret, including the field name
# 
sm_read() {
  local mount="${1:-}"
  local path="${2:-}"

  local usage="Usage: Usage: sm_read <mount> <path>"
  local vault_args="-mount=\"${mount}\" \"${path}\""

  if [ -z "$mount" ]; then
    >&2 echo "Error: Mount is required for ${vault_args}. ${usage}"
    return 1
  fi

  if [ -z "$path" ]; then
    >&2 echo "Error: Path is required for ${vault_args}. ${usage}"
    return 1
  fi
  
  # Check if path is valid: don't start with a slash, at least on slash, does not end with a slash
  if [[ ! "$path" =~ ^[^/]+/.+[^/]$ ]]; then
    >&2 echo "Error: Path is invalid, slash issue for ${vault_args}. ${usage}"
    return 1
  fi

  # Extract secret path and field
  local vault_secret_path="${path%/*}"
  local field="${path##*/}"
  data=$(vault kv get -mount="${mount}" -field="${field}" "${vault_secret_path}" 2>/dev/null)
  if [ "$?" != "0" ]; then
    >&2 echo "ERROR: vault entry not found: vault kv get -mount=\"${mount}\" -field=\"${field}\" \"${vault_secret_path}\""
    return 1
  fi
  echo -n "${data}"
  return 0
}

# 
# Usage: sm_write <mount> <path> key1=value1 key2=value2 ...
# NOTE: path is the full path to the secret without the field name
# 
sm_write() {
  local mount="${1:-}"
  local path="${2:-}"
  # local fields=${*:3}
  shift 2

  local fields=""
  for arg in "$@"; do
    if [ -n "$fields" ]; then
      fields="${fields} ${arg}"
    else
      fields="${arg}"
    fi
  done

  local usage="Usage: sm_write <mount> <path> [<key>=<secret> | <key>=@<secret file> | @<secret file>]"

  local vault_args="-mount=\"${mount}\" \"${path}\" \"${fields}\""

  if [ -z "$mount" ]; then
    >&2 echo "Error: Mount is required for ${vault_args}. ${usage}"
    return 1
  fi

  if [ -z "$path" ]; then
    >&2 echo "Error: Path is required for ${vault_args}. ${usage}"
    return 1
  fi

  if [ -z "$fields" ]; then
    >&2 echo "Error: fields are required for ${vault_args}. ${usage}"
    return 1
  fi

  test_file() {
    local secrets_file="${1}"
    if [ ! -f "$secrets_file" ]; then
      >&2 echo "Error: File with secrets not found: ${secrets_file}"
      return 1
    fi
    if [ ! -s "$secrets_file" ]; then
      >&2 echo "Error: Secrets file is empty: ${secrets_file}"
      return 1
    fi
  }
  OLDIFS=$IFS
  IFS=' '
 
  for field in ${fields}; do
    local key="${field%%=*}"
    local value=""
    if echo "${field}" | grep -q "=" > /dev/null; then
      value="${field#*=}"
    fi

    if [[ -z "$key" || -z "$value" ]] && [[ "$key" != @* && "$value" != @* ]]; then
      >&2 echo "Error: Field key '$key' or value '$value' empty for ${vault_args}"
      return 1
    fi
    if [[ "$value" == @* ]]; then
      local secrets_file="${value#@}"
      ! test_file "${secrets_file}" && return 1
    fi
    if [[ "$key" == @* ]]; then
      local secrets_file="${key#@}"
      ! test_file "${secrets_file}" && return 1
    fi
  done
  IFS=$OLDIFS

  write_to_vault() {
    local method=$1
    eval vault kv "${method}" -mount="${mount}" "${path}" "${fields}" &>/dev/null
  }
  local method="put"
  local secret_data
  secret_data="$(vault kv get -format="json" -mount="${mount}" "${path}" 2>/dev/null)"  || true 
  if [ -z "${secret_data}" ]; then
    >&2 echo "INFO: vault entry not found: add path: ${path}"
    write_to_vault "${method}"
    return 0
  fi

  secret_value=$(echo "${secret_data}" | jq -r '.data.data')
  [ "${secret_value}" != "null" ] && \
    method="patch"
  write_to_vault "${method}"
  if [ "$?" == "0" ]; then
    >&2 echo "INFO: Secret written to Vault: vault kv ${method} -mount=\"${mount}\" \"${path}\" \"${fields}\""
  else
    >&2 echo "ERROR: writing secret to Vault: ${vault_args}"
  fi
}