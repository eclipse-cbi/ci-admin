#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2021 Eclipse Foundation and others.
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

#TODO: use pass wrapper

# read local config
LOCAL_CONFIG="${HOME}/.cbi/config"
if [[ ! -f "${LOCAL_CONFIG}" ]]; then
  echo "ERROR: File '$(readlink -f "${LOCAL_CONFIG}")' does not exists"
  echo "Create one to configure db and file server credentials. Example:"
  echo '{"db_server": {"server": "myserver", "user": "user", "mysql_user": "username", "mysql_pw": "<path in pass>"}}' | jq -M
fi

DB_SERVER="$(jq -r '.["db_server"]["server"]' "${LOCAL_CONFIG}")"
DB_SERVER_USER="$(jq -r '.["db_server"]["user"]' "${LOCAL_CONFIG}")"
DB_SERVER_MYSQL_USER="$(jq -r '.["db_server"]["mysql_user"]' "${LOCAL_CONFIG}")"
DB_SERVER_MYSQL_PW="$(jq -r '.["db_server"]["mysql_pw"]' "${LOCAL_CONFIG}")"


help() {
  printf "Available commands:\n"
  printf "Command\t\t\tDescription\n\n"
  printf "add_jipp\t\tAdd JIPP to DB.\n"
  printf "remove_jipp\t\tRemove JIPP from DB.\n"
  exit 0
}

_query_db() {
  local project_name="${1:-}"

  if [ -z "${project_name}" ]; then
    printf "ERROR: a project name must be given.\n"
    exit 1
  fi

  local mysqlQuery="${2:-}"
  local queryExpect="${3:-}"

  local user="${DB_SERVER_USER}"
  local server="${DB_SERVER}"
  local mysqlUser="${DB_SERVER_MYSQL_USER}"
  local mysqlPw="${DB_SERVER_MYSQL_PW}"

  local userPrompt="$user@$server:~> *"
  local mysqlPasswordPrompt="Enter \[Pp\]assword: *"
  local mysqlPrompt="MariaDB \[eclipsefoundation\]> *"

  local mysqlQueryCheck="SELECT * FROM ProjectServices WHERE ProjectID=\\\"$project_name\\\";"

  expect -c "
  #5 seconds timeout
  set timeout 5
  
  # ssh to remote
  spawn ssh $user@$server

  expect {
    #TODO: only works one time
    -re \"passphrase\" {
      interact -o \"\r\" return
    }
  }
  expect -re \"$userPrompt\"

  # use mysql
  send \"mysql -u $mysqlUser -p -h foundation eclipsefoundation\r\"
  interact -o -nobuffer -re \"$mysqlPasswordPrompt\" return
  send \"[exec pass $mysqlPw]\r\"
  expect -re \"$mysqlPrompt\"
  
  send \"$mysqlQuery\"
  expect -re \"Query OK, 1 row affected*\"

  send \"$mysqlQueryCheck\r\"
  #TODO: fail if expect fails?
  expect -re \"$queryExpect*\"

  # exit mysql and ssh
  send \"exit\rexit\r\"
  expect eof
"

}

add_jipp() {
  local project_name="${1:-}"
  local mysqlQuery="INSERT INTO ProjectServices (ProjectID, ServiceType, ServerHost) values (\\\"$project_name\\\", \\\"jipp\\\", \\\"okd\\\");\r"
  local queryExpect="1 row in set"

  echo "Adding ${project_name} to ProjectServices DB..."

  _query_db "${project_name}" "${mysqlQuery}" "${queryExpect}"
}

remove_jipp() {
  local project_name="${1:-}"
  local mysqlQuery="DELETE FROM ProjectServices WHERE ProjectID = \\\"$project_name\\\";"
  local queryExpect="Empty set"

  echo "Removing ${project_name} from ProjectServices DB..."

  _query_db "${project_name}" "${mysqlQuery}" "${queryExpect}"
}

"$@"

# show help menu, if no first parameter is given
if [[ -z "${1:-}" ]]; then
  help
fi
