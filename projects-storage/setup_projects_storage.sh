#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2022 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html,
# or the MIT License which is available at https://opensource.org/licenses/MIT.
# SPDX-License-Identifier: EPL-2.0 OR MIT
#*******************************************************************************

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'
SCRIPT_FOLDER="$(dirname "$(readlink -f "${0}")")"

CI_ADMIN_ROOT="${SCRIPT_FOLDER}/.."

#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../pass/pass_wrapper.sh"
#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../utils/common.sh"

PROJECT_NAME="${1:-}"

# check that project name is not empty
if [[ -z "${PROJECT_NAME}" ]]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

FILE_SERVER="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "server" "file_server")"
FILE_SERVER_USER="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "user" "file_server")"
FILE_SERVER_PW="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "pw" "file_server")"
FILE_SERVER_PW_ROOT="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "pw_root" "file_server")"
FILE_SERVER_PW_LDAP="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "pw_ldap" "file_server")"

check_genie_user() {
  local project_name="${1:-}"

  local user="${FILE_SERVER_USER}"
  local server="${FILE_SERVER}"
  local pw="${FILE_SERVER_PW}"

  local short_name="${project_name##*.}"
  local genie_user="genie.${short_name}"

  local userPrompt="$user@projects-storage:~$*"
  local passwordPrompt="\[Pp\]assword: *"

  echo
  echo "Checks for ${genie_user}:"

  expect -c "
  spawn ssh ${user}@${server} /bin/bash

  expect {
    -re \"$passwordPrompt\" {
      #interact -o -nobuffer -re \"$passwordPrompt\" return
      send [exec pass $pw]\r
    }
    #TODO: only works one time
    -re \"passphrase\" {
      interact -o \"\r\" return
    }
  }
  expect -re \"$userPrompt\"

  send \"test -d '/opt/public/hipp/homes/${genie_user}' && printf 'Genie homedir: exists\n' || printf 'Genie homedir: missing!\n'\r\"
  send \"test -d '/home/data/httpd/download.eclipse.org/${short_name}' && printf 'Download directory: exists\n' || printf 'Download directory: missing!\n'\r\"
  send \"id '${genie_user}' | grep '${project_name}' && printf 'Member of group: exists\n' || printf 'Member of group: missing!\n'\r\"

  expect eof
"
}

fix_ldap() {
  local project_name="${1:-}"

  local user="${FILE_SERVER_USER}"
  local server="${FILE_SERVER}"
  local pw="${FILE_SERVER_PW}"
  local pwRoot="${FILE_SERVER_PW_ROOT}"
  local pwLdap="${FILE_SERVER_PW_LDAP}"

  local short_name="${project_name##*.}"
  local genieUser="genie.${short_name}"

  local userPrompt="$user@projects-storage:~$*"
  local passwordPrompt="\[Pp\]assword: *"
  local serverRootPrompt="$server:~ # *"
  local ldapPasswordPrompt="LDAP \[Pp\]assword: *"

  echo
  echo "Fix LDAP ${genieUser}:"

  # /usr/bin/env expect<<EOF can not be used
  # "The problem is in expect << EOF. With expect << EOF, expect's stdin is the here-doc rather than a tty.
  # But the interact command only works when expect's stdin is a tty."

  expect -c "
  #5 seconds timeout
  set timeout 5

  # ssh to remote
  spawn ssh $user@$server

  expect {
    -re \"$passwordPrompt\" {
      #interact -o -nobuffer -re \"$passwordPrompt\" return
      send [exec pass $pw]\r
    }
    #TODO: only works one time
    -re \"passphrase\" {
      interact -o \"\r\" return
    }
  }
  expect -re \"$userPrompt\"

  # su to root
  send \"su -\r\"
  interact -o -nobuffer -re \"$passwordPrompt\" return
  send \"[exec pass $pwRoot]\r\"
  expect -re \"$serverRootPrompt\"

  # fix LDAP
  #TODO: fix expect: spawn id exp4 not open issues
  send \"./fix_ldap.sh $genieUser\r\"
  interact -o -nobuffer -re \"$ldapPasswordPrompt\" return
  send_user \"\n\"
  send \"[exec pass $pwLdap]\r\"

  # exit su and exit ssh
  send \"exit\rexit\r\"

  expect eof
"
}

add_pub_key() {
  #add public key to genie's .ssh/authorized_keys
  local project_name="${1:-}"

  local user="${FILE_SERVER_USER}"
  local server="${FILE_SERVER}"
  local pw="${FILE_SERVER_PW}"
  local pwRoot="${FILE_SERVER_PW_ROOT}"

  local short_name="${project_name##*.}"
  local genieUser="genie.${short_name}"

  local userPrompt="${user}@${server}~$*"
  local passwordPrompt="\[Pp\]assword: *"
  local serverRootPrompt="$server:~ # *"
  local geniePrompt="${genieUser}@${server}:~*"

  # local id_rsa_pub="cbi-pass/bots/${project_name}/projects-storage.eclipse.org/id_rsa.pub"

  id_rsa_pub="$(passw cbi "bots/${project_name}/projects-storage.eclipse.org/id_rsa.pub")"

  expect -c "
  #5 seconds timeout
  set timeout 5

  # ssh to remote
  spawn ssh $user@$server

  expect {
    -re \"$passwordPrompt\" {
      #interact -o -nobuffer -re \"$passwordPrompt\" return
      send [exec pass $pw]\r
    }
    #TODO: only works one time
    -re \"passphrase\" {
      interact -o \"\r\" return
    }
  }
  expect -re \"$userPrompt\"

  # su to root
  send \"su -\r\"
  interact -o -nobuffer -re \"$passwordPrompt\" return
  send [exec pass $pwRoot]\r
  expect -re \"$serverRootPrompt\"

  # su to genie.user
  send \"su - $genieUser\r\"
  expect -re \"$geniePrompt\"

  # add SSH pub key to .ssh/authorized_keys
  send \"grep -qF '$id_rsa_pub' ~/.ssh/authorized_keys && echo 'authorized_keys is already configured' || echo [exec echo $id_rsa_pub] >> .ssh/authorized_keys\r\"
  send \"cat .ssh/authorized_keys\r\"

  # exit su, exit su and exit ssh
  send \"exit\rexit\rexit\r\"
  expect eof
"
}

## MAIN ##

#TODO: assume that check_genie_user and fix_ldap are no longer required
check_genie_user "${PROJECT_NAME}"
fix_ldap "${PROJECT_NAME}"
"${SCRIPT_FOLDER}/../pass/add_creds.sh" projects_storage "${PROJECT_NAME}" || :
add_pub_key "${PROJECT_NAME}"
printf "\nDone.\n"