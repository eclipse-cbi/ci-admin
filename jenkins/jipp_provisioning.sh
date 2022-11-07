#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2021 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html,
# or the MIT License which is available at https://opensource.org/licenses/MIT.
# SPDX-License-Identifier: EPL-2.0 OR MIT
#*******************************************************************************

# Provision a new Jenkins instance on JIRO

#  - check genie user on projects-storages
#    - check if genie home dir exists
#    - check if download dir exists
#    - check if genie user is part of the project LDAP/Unix group
#  - fix LDAP on projects-storage
#  - create projects-storage credentials and add them to pass
#  - add pub key to genie to .ssh/authorized_keys in home dir on projects-storage
#  - create new JIRO JIPP
#  - ask if GitHub credentials should be set up
#  - ask if OSSRH credentials should be set up
#  - show issue template


# TODO:
# * make scripts robust (work when run multiple times)
# * fix pass path for good

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
CI_ADMIN_ROOT="${SCRIPT_FOLDER}/../"

#TODO: refactor expect scripts?

PROJECT_NAME="${1:-}"
DISPLAY_NAME="${2:-}"

usage() {
  printf "Usage: %s project_name display_name\n" "${SCRIPT_NAME}"
  printf "\t%-16s project name (e.g. technology.cbi for CBI project).\n" "project_name"
  printf "\t%-16s display name (e.g. 'Eclipse CBI' for CBI project).\n" "display_name"
}

# check that project name is not empty
if [ -z "${PROJECT_NAME}" ]; then
  printf "ERROR: a project name must be given.\n"
  usage
  exit 1
fi

if [ -z "${DISPLAY_NAME}" ]; then
  printf "ERROR: a display name must be given.\n"
  usage
  exit 1
fi

LOCAL_CONFIG="${HOME}/.cbi/config"

if [[ ! -f "${LOCAL_CONFIG}" ]]; then
  echo "ERROR: File '$(readlink -f "${LOCAL_CONFIG}")' does not exists"
  echo "Create one to configure the location of the JIRO root dir and file server credentials. Example:"
  echo '{"jiro-root-dir": "/path/to/jiro/rootdir", "file_server": {"server": "myserver", "user": "user2", "pw": "<path in pass>", "pw_root": "<path in pass>", "pw_ldap": "<path in pass>"}}' | jq -M
  exit 1
fi

JIRO_ROOT_FOLDER="$(jq -r '."jiro-root-dir"' < "${LOCAL_CONFIG}")"

if [[ -z "${JIRO_ROOT_FOLDER}" ]] || [[ "${JIRO_ROOT_FOLDER}" == "null" ]]; then
  printf "ERROR: 'jiro-root-dir' must be set in %s.\n" "${LOCAL_CONFIG}"
  exit 1
fi

FILE_SERVER="$(jq -r '.["file_server"]["server"]' "${LOCAL_CONFIG}")"
FILE_SERVER_USER="$(jq -r '.["file_server"]["user"]' "${LOCAL_CONFIG}")"
FILE_SERVER_PW="$(jq -r '.["file_server"]["pw"]' "${LOCAL_CONFIG}")"
FILE_SERVER_PW_ROOT="$(jq -r '.["file_server"]["pw_root"]' "${LOCAL_CONFIG}")"
FILE_SERVER_PW_LDAP="$(jq -r '.["file_server"]["pw_ldap"]' "${LOCAL_CONFIG}")"

if [[ -z "${FILE_SERVER}" ]] || [[ "${FILE_SERVER}" == "null" ]]; then
  printf "ERROR: 'file_server/server' must be set in %s.\n" "${LOCAL_CONFIG}. Example:"
  echo '{"file_server": {"server": "myserver", "user": "user2", "pw": "<path in pass>", "pw_root": "<path in pass>", "pw_ldap": "<path in pass>"}}' | jq -M
  exit 1
fi

check_genie_user() {
  local project_name="${1:-}"

  local user="${FILE_SERVER_USER}"
  local server="${FILE_SERVER}"
  
  local short_name="${project_name##*.}"
  local genie_user="genie.${short_name}"

  echo
  echo "Checks for ${genie_user}:"
  
  ssh "${user}"@"${server}" /bin/bash << EOF
  if [[ -d "/opt/public/hipp/homes/${genie_user}" ]]; then
    printf "Genie homedir:\t\texists\n"
  else
    printf "Genie homedir:\t\tmissing!\n"
  fi
  if [[ -d "/home/data/httpd/download.eclipse.org/${short_name}" ]]; then
    printf "Download directory:\texists\n"
  else
    printf "Download directory:\tmissing!\n"
  fi
  if id "${genie_user}" | grep "${project_name}" &>/dev/null; then
    printf "Member of group:\texists\n"
  else
    printf "Member of group:\tmissing!\n"
  fi
EOF
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

  local id_rsa_pub="cbi-pass/bots/${project_name}/projects-storage.eclipse.org/id_rsa.pub"

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
  #TODO: do not add key if it already exists
  #TODO: fix quoting
  send \"echo [exec pass $id_rsa_pub] >> .ssh/authorized_keys\r\"
  send \"cat .ssh/authorized_keys\r\"
  
  # exit su, exit su and exit ssh
  send \"exit\rexit\rexit\r\"
  expect eof
"
}

setup_github() {
  printf "\n\n### Setting up GitHub bot credentials...\n"
  pushd "${CI_ADMIN_ROOT}/pass"
  ./add_creds.sh github "${PROJECT_NAME}"
  ./add_creds.sh github_ssh "${PROJECT_NAME}"
  popd
  printf "\n"
}

setup_ossrh() {
  printf "\n### Setting up OSSRH credentials...\n"
  pushd "${CI_ADMIN_ROOT}/pass"
  ./add_creds_gpg.sh "${PROJECT_NAME}" "${DISPLAY_NAME} Project"
  ./add_creds.sh ossrh "${PROJECT_NAME}"
  #dump secret-subkeys
  mkdir "${PROJECT_NAME}"
  pass "cbi-pass/bots/${PROJECT_NAME}/gpg/secret-subkeys.asc" > "${PROJECT_NAME}/secret-subkeys.asc"
  echo "Exported secret-subkeys.asc to ${PROJECT_NAME}/secret-subkeys.asc."
  popd
  "${JIRO_ROOT_FOLDER}/jenkins-create-credentials.sh" "${PROJECT_NAME}"
  printf "\n"
  echo "Added secret-subkeys.asc to JIPP (manually for now)?"
  read -p "Press enter to continue or CTRL-C to stop the script"
  printf "\n"
}

question() {
  local message="${1:-}"
  local action="${2:-}"
  read -p "Do you want to ${message}? (Y)es, (N)o, E(x)it: " yn
  case $yn in
    [Yy]* ) ${action};;
    [Nn]* ) return ;;
    [Xx]* ) exit 0;;
        * ) echo "Please answer (Y)es, (N)o, E(x)it"; question "${message}" "${action}";
  esac
}

issue_template() {
  local short_name="${PROJECT_NAME##*.}"
  cat <<EOF

Post the following on the corresponding GitLab issue:
-----------------------------------------------------

The ${DISPLAY_NAME} JIPP on Jiro is available here now:

=> https://ci.eclipse.org/${short_name}

PLEASE NOTE:
* Publishing to download.eclipse.org requires access via SCP. We've added the credentials to the JIPP. Please see https://wiki.eclipse.org/Jenkins#How_do_I_deploy_artifacts_to_download.eclipse.org.3F for more info.

* To simplify setting up jobs on our cluster-based infra, we provide a pod template that can also be used with freestyle jobs. The pod template has the label "centos-7" which can be specified in the job configuration under "Restrict where this project can be run". The image contains more commonly used dependencies than the default “basic” pod template.

* You can find more info about Jenkins here: https://wiki.eclipse.org/Jenkins

Please let us know if you need any additional plug-ins.

-----------------------------------------------------

EOF
read -rsp $'Once you are done, press any key to continue...\n' -n1
}

## MAIN ##

echo "Connected to cluster?"
read -p "Press enter to continue or CTRL-C to stop the script"

#TODO: can this be done differently?
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa

#TODO: assume that check_genie_user and fix_ldap are no longer required
check_genie_user "${PROJECT_NAME}"
fix_ldap "${PROJECT_NAME}"

#FIXME: projects_storage creds should not be created, if they already exist

pushd "${CI_ADMIN_ROOT}/pass"
./add_creds.sh projects_storage "${PROJECT_NAME}" || : # if creds already exist, ignore exit code 1
popd

add_pub_key "${PROJECT_NAME}"

"${JIRO_ROOT_FOLDER}/incubation/create_new_jiro_jipp.sh" "${PROJECT_NAME}" "${DISPLAY_NAME}"

# ask if GitHub bot credentials should be created
question "setup GitHub bot credentials" "setup_github"
#TODO: run /ci-admin/github/setup_jenkins_github_integration.sh

# ask if OSSRH/gpg credentials should be created
question "setup OSSRH credentials" "setup_ossrh"

#TODO: only if github or ossrh setup was executed
# create Jenkins credentials
"${JIRO_ROOT_FOLDER}/jenkins-create-credentials.sh" "${PROJECT_NAME}"

"${JIRO_ROOT_FOLDER}/jenkins-create-credentials-token.sh" "auto" "${PROJECT_NAME}"

issue_template

#TODO: commit changes to JIRO repo
pushd "${JIRO_ROOT_FOLDER}"
git add "${JIRO_ROOT_FOLDER}/instances/${PROJECT_NAME}"
#git commit -m "Provisioning JIPP for project ${PROJECT_NAME}"
popd

rm -rf "${PROJECT_NAME}"