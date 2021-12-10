#!/usr/bin/env bash

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

maven_version="${1:-}"
file_name="apache-maven-${maven_version}-bin.tar.gz"
download_url="https://downloads.apache.org/maven/maven-3/${maven_version}/binaries/${file_name}"

MAVEN_TOOLS_PATH="/home/data/cbi/buildtools/apache-maven"

# check that maven version is not empty
if [ -z "${maven_version}" ]; then
  printf "ERROR: a maven version must be given (eg. '3.8.4').\n"
  exit 1
fi

# read .localconfig
local_config_path="${SCRIPT_FOLDER}/../.localconfig"
if [[ ! -f "${local_config_path}" ]]; then
  echo "ERROR: File '$(readlink -f "${local_config_path}")' does not exists"
  echo "Create one to configure db and file server credentials. Example:"
  echo '{"backend_server": {"server": "myserver", "user": "user", "pw": "<path in pass>", "pw_root": "<path in pass>"}}' | jq -M
  exit 1
fi

BACKEND_SERVER="$(jq -r '.["backend_server"]["server"]' "${local_config_path}")"
BACKEND_SERVER_USER="$(jq -r '.["backend_server"]["user"]' "${local_config_path}")"
BACKEND_SERVER_PW="$(jq -r '.["backend_server"]["pw"]' "${local_config_path}")"
BACKEND_SERVER_PW_ROOT="$(jq -r '.["backend_server"]["pw_root"]' "${local_config_path}")"

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
  local file_name="apache-maven-${maven_version}-bin.tar.gz"

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
  #5 seconds timeout
  set timeout 5

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
  send \"tar xzf /tmp/${file_name} -C ${MAVEN_TOOLS_PATH}\r\"
  send \"mv ${MAVEN_TOOLS_PATH}/apache-maven-${maven_version} ${MAVEN_TOOLS_PATH}/${maven_version}\r\"
  # TODO: only remove when target dir exists as expected
  send \"rm /tmp/${file_name}\r\"
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

#download Maven
wget -c "${download_url}"

if [[ ! -f "${file_name}" ]]; then
  echo "${file_name} does not exist! Error during download?"
  exit 1
fi

#scp tar.gz to bambam
scp "${file_name}" "bambam:/tmp/"

update "${maven_version}"

# remove local tar.gz
rm -f "${file_name}"