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

maven_version="${1:-}"
FILE_NAME="apache-maven-${maven_version}-bin.tar.gz"
DOWNLOAD_URL="https://archive.apache.org/dist/maven/maven-3/${maven_version}/binaries/${FILE_NAME}"

MAVEN_TOOLS_PATH="/home/data/cbi/buildtools/apache-maven"

# check that maven version is not empty
if [ -z "${maven_version}" ]; then
  printf "ERROR: a maven version must be given (eg. '3.8.4').\n"
  exit 1
fi

# read local config
LOCAL_CONFIG="${HOME}/.cbi/config"
if [[ ! -f "${LOCAL_CONFIG}" ]]; then
  echo "ERROR: File '$(readlink -f "${LOCAL_CONFIG}")' does not exists"
  echo "Create one to configure db and file server credentials. Example:"
  echo '{"backend_server": {"server": "myserver", "user": "user", "pw": "<path in pass>", "pw_root": "<path in pass>"}}' | jq -M
  exit 1
fi

JIRO_ROOT_FOLDER="$(jq -r '."jiro-root-dir"' < "${LOCAL_CONFIG}")"

BACKEND_SERVER="$(jq -r '.["backend_server"]["server"]' "${LOCAL_CONFIG}")"
BACKEND_SERVER_USER="$(jq -r '.["backend_server"]["user"]' "${LOCAL_CONFIG}")"
BACKEND_SERVER_PW="$(jq -r '.["backend_server"]["pw"]' "${LOCAL_CONFIG}")"
BACKEND_SERVER_PW_ROOT="$(jq -r '.["backend_server"]["pw_root"]' "${LOCAL_CONFIG}")"

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

download_maven

#scp tar.gz to backend server
scp "${FILE_NAME}" "${BACKEND_SERVER_USER}@${BACKEND_SERVER}:/tmp/"

update "${maven_version}"

update_jiro_template "${maven_version}"

# TODO: create HelpDesk issue response template

# remove local tar.gz
rm -f "${FILE_NAME}"
