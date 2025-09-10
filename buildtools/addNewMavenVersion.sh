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
SCRIPT_FOLDER="$(dirname "$(readlink -f "${0}")")"
CI_ADMIN_ROOT="${SCRIPT_FOLDER}/.."

#shellcheck disable=SC1091
source "${SCRIPT_FOLDER}/../utils/common.sh"

JIRO_ROOT_FOLDER="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "jiro-root-dir")"
BACKEND_SERVER="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "server" "backend_server")"
BACKEND_SERVER_USER="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "user" "backend_server")"
BACKEND_SERVER_PW="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "pw" "backend_server")"
BACKEND_SERVER_PW_ROOT="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "pw_root" "backend_server")"

maven_version="${1:-}"
FILE_NAME="apache-maven-${maven_version}-bin.tar.gz"
DOWNLOAD_URL="https://archive.apache.org/dist/maven/maven-3/${maven_version}/binaries/${FILE_NAME}"

MAVEN_TOOLS_PATH="/home/data/cbi/buildtools/apache-maven"

# check that maven version is not empty
if [ -z "${maven_version}" ]; then
  printf "ERROR: a maven version must be given (eg. '3.8.4').\n"
  exit 1
fi

download_maven() {
  wget -c "${DOWNLOAD_URL}"
  if [[ ! -f "${FILE_NAME}" ]]; then
    echo "${FILE_NAME} does not exist! Error during download?"
    exit 1
  fi
}

update_latest_question() {
  local version="${1:-}"
  read -p "Do you want to update the latest symlink to point to Maven ${version}? (Y)es, (N)o, E(x)it: " yn
  case $yn in
    [Yy]* ) echo "true" ;;
    [Nn]* ) echo "false" ;;
    [Xx]* ) exit 0;;
        * ) echo "Please answer (Y)es, (N)o, E(x)it"; update_latest_question "${version}";
  esac
}

update() {
  local maven_version="${1:-}"
  local FILE_NAME="apache-maven-${maven_version}-bin.tar.gz"

  local user="${BACKEND_SERVER_USER}"
  local server="${BACKEND_SERVER}"
  local pw="${BACKEND_SERVER_PW}"
  local pwRoot="${BACKEND_SERVER_PW_ROOT}"

  local userPrompt="$user@$server:~> *"
  local passwordPrompt="\[Pp\]assword: *"
  local serverRootPrompt="$server:~ # *"

  local update_latest
  update_latest="$(update_latest_question "${maven_version}")"
  # exit if update_latest is not set (question -> exit)
  if [[ -z "${update_latest}" ]]; then
    exit 0
  fi

  expect -c "
  #10 seconds timeout
  set timeout 10

  # ssh to remote
  spawn ssh $user@$server

  expect {
    -re \"$passwordPrompt\" {
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

  # extract file
  send \"tar xzf /tmp/${FILE_NAME} -C ${MAVEN_TOOLS_PATH}\r\"
  send \"mv ${MAVEN_TOOLS_PATH}/apache-maven-${maven_version} ${MAVEN_TOOLS_PATH}/${maven_version}\r\"
  # TODO: only remove when target dir exists as expected
  send \"rm /tmp/${FILE_NAME}\r\"
  send \"ls -al ${MAVEN_TOOLS_PATH}\r\"
  if { \"$update_latest\" == \"true\" } {
    send \"cd ${MAVEN_TOOLS_PATH}\r\"
    send \"ln -sfn ${maven_version} latest\r\"
    send \"ls -al latest\r\"
  }

  # exit su, exit su and exit ssh
  send \"exit\rexit\rexit\r\"
  expect eof
"
}

update_jiro_template() {
  local maven_version="${1:-}"
  echo "Updating JIRO tools-maven.hbs template..."
  # check if entry already exists
  if grep "apache-maven-${maven_version}" "${JIRO_ROOT_FOLDER}/templates/jenkins/partials/tools-maven.hbs" > /dev/null; then
    echo "Entry for apache-maven-${maven_version} already exists! Skipping..."
    return
  fi
  # update /jiro/templates/jenkins/partials/tools-maven.hbs
  maven_template="${JIRO_ROOT_FOLDER}/templates/jenkins/partials/tools-maven.hbs"
  yq e ".maven.installations += [{\"name\": \"apache-maven-${maven_version}\", \"home\": \"/opt/tools/apache-maven/${maven_version}\"}]" -i "${maven_template}" 
  # fix order of entries and quotes
  yq '.maven.installations |= sort_by(.name) | .maven.installations |= reverse | .. style="double"' -i "${maven_template}"
  pushd "${JIRO_ROOT_FOLDER}"
  git add "templates/jenkins/partials/tools-maven.hbs"
  git commit -m "Add Maven version ${maven_version}"
  popd
  echo "TODO: push change in JIRO repo"
  read -rsp $'Once you are done, press any key to continue...\n' -n1
}

eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa

#TODO: check if version already exists on backend server

download_maven

#scp tar.gz to backend server
scp "${FILE_NAME}" "${BACKEND_SERVER_USER}@${BACKEND_SERVER}:/tmp/"

update "${maven_version}"

update_jiro_template "${maven_version}"

# TODO: create HelpDesk issue response template

# remove local tar.gz
rm -f "${FILE_NAME}"
