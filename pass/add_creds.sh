#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2021 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

source "${SCRIPT_FOLDER}/pass_wrapper.sh"

_verify_inputs() {
  local project_name="${1:-}"

  # check that project name is not empty
  if [ "${project_name}" == "" ]; then
    printf "ERROR: a project name must be given.\n"
    exit 1
  fi

  # check that project name contains a dot
  if [[ "${project_name}" != *.* ]]; then
    printf "ATTENTION: the full project name does not contain a dot (e.g. technology.cbi). Please double-check that this is intentional!\n"
    read -p "Press enter to continue or CTRL-C to stop the script"
  fi
}

_check_pw_does_not_exist() {
  local project_name="${1:-}"
  local path="${2:-}"
  local pw_store_path="bots/${project_name}/${path}"

  # check that the entries do not exist yet
  if passw cbi "${pw_store_path}" &> /dev/null ; then
    printf "%s credentials for %s already exist. Skipping creation...\n" "${path}" "${project_name}"
    return 1
  fi
  return 0
}

_show_info() {
  local project_name="${1:-}"
  local site="${2:-}"
  local email="${3:-}"
  local user="${4:-}"
  local short_name="${project_name##*.}"
  
  printf "Project name: %s\n" "${project_name}"
  printf "Short name: %s\n" "${short_name}"
  printf "%s email: %s\n" "${site}" "${email}"
  printf "%s user: %s\n" "${site}" "${user}"
}

_add_to_pw_store() {
  local project_name="${1:-}"
  local site="${2:-}"
  local email="${3:-}"
  local user="${4:-}"
  local pw="${5:-}"

  local pw_store_path="bots/${project_name}/${site}"

  echo "${email}" | passw cbi insert --echo "${pw_store_path}/email"
  echo "${user}" | passw cbi insert --echo "${pw_store_path}/username"
  echo "${pw}" | passw cbi insert --echo "${pw_store_path}/password"
}

_generate_ssh_keys() {
  local project_name="${1:-}"
  local site="${2:-}"
  local email="${3:-}"
  local user="${4:-}"
  local short_name="${project_name##*.}"
  local temp_path="/tmp/${short_name}_id_rsa"

  # shellcheck disable=SC1003
  pwgen -1 -s -r '\\"-' -y 64 | passw cbi insert -m "${pw_store_path}/id_rsa.passphrase"
  passw cbi "${pw_store_path}/id_rsa.passphrase" | "${SCRIPT_FOLDER}"/../ssh-keygen-ni.sh -C "${email}" -f "${temp_path}"

  # Insert private and public key into pw store
  cat "${temp_path}" | passw cbi insert -m "${pw_store_path}/id_rsa"
  cat "${temp_path}.pub" | passw cbi insert -m "${pw_store_path}/id_rsa.pub"
  rm "${temp_path}"*
  # Add user/email (if it does not exist yet)
  if _check_pw_does_not_exist "${project_name}" "${site}/username"; then
    echo "${user}" | passw cbi insert --echo "${pw_store_path}/username"
  fi
  if _check_pw_does_not_exist "${project_name}" "${site}/email"; then
    echo "${email}" | passw cbi insert --echo "${pw_store_path}/email"
  fi
}

## commands

help() {
  printf "Available commands:\n"
  printf "Command\t\t\tDescription\n\n"
  printf "user_pw\t\t\tCreate any credentials (username/password).\n"
  printf "user_pw_prompt\t\tCreate any credentials (username/password).\n"
  printf "generic\t\t\tCreate any credentials for a site (username/password) e.g: ./pass/add_creds.sh \""generic\"" \""iot.4diac\"" \""npmjs.com\"".\n"
  printf "generic_container\t\t\tCreate any credentials for a container site (docker, quay.io, ...) (username/password) e.g: ./pass/add_creds.sh \""generic_container\"" \""iot.4diac\"" \""quay.io\"".\n"
  printf "generic_ssh\t\t\tCreate any SSH credentials for a site (SSH keypair) e.g: ./pass/add_creds.sh \""generic_ssh\"" \""iot.4diac\"" \""quay.io\"".\n"
  printf "ssh_keys\t\tCreate any SSH credentials (SSH keypair).\n"
  printf "gerrit\t\t\tCreate Gerrit credentials (SSH keypair).\n"
  printf "github\t\t\tCreate GitHub credentials (username/password).\n"
  printf "github_ssh\t\tCreate SSH credentials for GitHub (SSH keypair).\n"
  printf "matrix\t\tCreate Matrix credentials for chat.eclipse.org (username/password).\n"
  printf "ossrh\t\t\tCreate credentials for OSSRH (username/password).\n"
  printf "projects_storage\tCreate SSH credentials for projects-storage.eclipse.org (SSH keypair).\n"
  printf "docker\t\t\tCreate credentials for docker.com (username/password).\n"
  printf "quay\t\t\tCreate credentials for quay.io (username/password).\n"
  exit 0
}

gerrit() {
  local project_name="${1:-}"
  local site="git.eclipse.org"
  local short_name="${project_name##*.}"
  local email="${short_name}-bot@eclipse.org"
  local user="eclipse-${short_name}-bot"
  local pw_store_path="bots/${project_name}/${site}"

  _verify_inputs "${project_name}"

  if _check_pw_does_not_exist "${project_name}" "${site}/username"; then
    _generate_ssh_keys "${project_name}" "${site}" "${email}" "${user}"
  fi

  _show_info "${project_name}" "${site}" "${email}" "${user}"

#TODO: fix behavior
  return_value=$(curl -s "https://${site}/r/accounts/${email}")
  if [[ ${return_value} == "Account '${email}' not found" ]]; then
    local bot_name
    read -p "Enter bot name (without the trailing 'Bot', e.g. 'CBI' for 'CBI Bot'): " bot_name
    echo
    printf "Creating Gerrit bot account...\n"
    # shellcheck disable=SC2029
    passw cbi "${pw_store_path}/id_rsa.pub" | ssh -p 29418 "${site}" "gerrit" "create-account" --full-name "'${bot_name} Bot'" --email "${email}" --ssh-key - "genie.${short_name}"
    printf "\nFlushing Gerrit caches..."
    ssh -p 29418 "${site}" "gerrit" "flush-caches"
    printf "Done.\n"
  else
    printf "Gerrit bot account %s already exists. Skipping creation...\n" "${email}"
    #printf "Adding SSH public key...\n"
    #passw cbi ${pw_store_path}/id_rsa.pub | ssh -p 29418 git.${forge}.org gerrit set-account --add-ssh-key - genie.${short_name}
    exit 1
  fi
}

generic() {
  local project_name="${1:-}"
  local site="${2:-}"
  local short_name="${project_name##*.}"
  local email="${short_name}-bot@eclipse.org"
  local user="eclipse-${short_name}-bot"

  user_pw "${project_name}" "${site}" "${email}" "${user}"
}

generic_container() {
  local project_name="${1:-}"
  local site="${2:-}"
  local short_name="${project_name##*.}"
  local email="${short_name}-bot@eclipse.org"
  local user="eclipse${short_name}"

  user_pw "${project_name}" "${site}" "${email}" "${user}"
}

generic_ssh() {
  local project_name="${1:-}"
  local site="${2:-}"
  local short_name="${project_name##*.}"
  local user="eclipse-${short_name}-bot"

  ssh_keys "${project_name}" "${site}"
}

github() {
  local project_name="${1:-}"
  local site="github.com"

  generic "${project_name}" "${site}" 
}

github_ssh() {
  local project_name="${1:-}"
  local site="github.com"

  generic_ssh "${project_name}" "${site}"
}

matrix() {
  local project_name="${1:-}"
  local site="matrix.eclipse.org"

  generic "${project_name}" "${site}"
}

ossrh() {
  local project_name="${1:-}"
  local site="oss.sonatype.org"

  generic "${project_name}" "${site}"
}

docker() {
  local project_name="${1:-}"
  local site="docker.com"

  generic_container "${project_name}" "${site}"
}

quay() {
  local project_name="${1:-}"
  local site="quay.io"

  generic_container "${project_name}" "${site}"
}

projects_storage() {
  local project_name="${1:-}"
  local site="projects-storage.eclipse.org"

  generic_ssh "${project_name}" "${site}"
}

ssh_keys() {
  local project_name="${1:-}"
  local site="${2:-}"
  local username="${3:-}" #optional
  local short_name="${project_name##*.}"
  local email="${short_name}-bot@eclipse.org"

  _verify_inputs "${project_name}"

  if [ -z "${site}" ]; then
    printf "ERROR: a site (e.g. 'gitlab.eclipse.org') must be given.\n"
    exit 1
  fi

  local pw_store_path="bots/${project_name}/${site}"
  #debug
  #echo "pw_store_path: ${pw_store_path}";

  if [ -z "${username}" ]; then
    echo "Username not given, using default: genie.${short_name}"
    user="genie.${short_name}"
  else
    user="${username}"
  fi

  # check that the entries do not exist yet
  if ! _check_pw_does_not_exist "${project_name}" "${site}/id_rsa"; then
    exit 1
  fi

  _show_info "${project_name}" "${site}" "${email}" "${user}"
  _generate_ssh_keys "${project_name}" "${site}" "${email}" "${user}"
}

user_pw() {
  local project_name="${1:-}"
  local site="${2:-}"
  local email="${3:-}"
  local user="${4:-}"
  local pw="${5:-}"

  _verify_inputs "${project_name}"
 
  if [ "${site}" == "" ]; then
    printf "ERROR: a site (e.g. docker.com) name must be given.\n"
    exit 1
  fi

  if [ "${email}" == "" ]; then
    printf "ERROR: an email must be given.\n"
    exit 1
  fi
  
  if [ "${user}" == "" ]; then
    printf "ERROR: a username must be given.\n"
    exit 1
  fi

  if ! _check_pw_does_not_exist "${project_name}" "${site}/username"; then
    exit 1
  fi
  _show_info "${project_name}" "${site}" "${email}" "${user}"

  # generate pw if not given
  if [[ -z "${pw}" ]]; then
    pw="$(pwgen -1 -s -y 24)"
  fi
  _add_to_pw_store "${project_name}" "${site}" "${email}" "${user}" "${pw}"
}

user_pw_prompt () {
  local project_name="${1:-}"
  local site="${2:-}"

  _verify_inputs "${project_name}"

  if [ "${site}" == "" ]; then
    printf "ERROR: a site (e.g. docker.com) name must be given.\n"
    exit 1
  fi

  echo -n "${site} email: "; read -r email
  echo -n "${site} username: "; read -r user
  read -p "Do you want to generate the password? (Y)es, (N)o, E(x)it: " yn
  case $yn in
    [Yy]* ) pw="$(pwgen -1 -s -y 24)";printf "%s password: %s\n" "${site}" "${pw}";;
    [Nn]* ) echo -n "${site} password: ";read -r pw;;
    [Xx]* ) exit;;
        * ) echo "Please answer (Y)es, (N)o, E(x)it";exit 1;
  esac

  user_pw "${project_name}" "${site}" "${email}" "${user}" "${pw}"
}


"$@"

# show help menu, if no first parameter is given
if [[ -z "${1:-}" ]]; then
  help
fi
