#! /usr/bin/env bash
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

project_name="${1:-}"
short_name=${project_name##*.}

if [ "${project_name}" == "" ]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

# Create temp dir
mkdir -p temp
pushd temp

question() {
  read -p "Which credentials should be changed? (P)rojects-storage, (G)it, Git(H)ub, E(x)it: " pghx
  case $pghx in
    [Pp]* ) domain="projects-storage.eclipse.org";;
    [Gg]* ) domain="git.eclipse.org";;
    [Hh]* ) domain="github.com";;
    [Xx]* ) exit;;
        * ) echo "Please answer (P)rojects-storage, (G)it, E(x)it"; question;;
  esac
}

question

echo "Replacing ${domain} credentials..."

pw_store_path="cbi-pass/bots/${project_name}/${domain}"

# Get private key from pass
pass "${pw_store_path}/id_rsa" > id_rsa
chmod 600 id_rsa

# get old pw from pass
old_pw=$(pass "${pw_store_path}/id_rsa.passphrase")

# overwrite old pw in pass with new pw without "\"
pwgen -1 -s -r '\' -y 64 | pass insert -m ${pw_store_path}/id_rsa.passphrase

new_pw=$(pass "${pw_store_path}/id_rsa.passphrase")

ssh-keygen -p -P "${old_pw}" -N "${new_pw}" -f id_rsa

# update private key in pass
cat id_rsa | pass insert -m "${pw_store_path}/id_rsa"
echo "Passphrase and private key have been updated in pass."

echo "TODO:"

if [[ "${domain}" == "git" ]]; then
  echo "* Update Gerrit settings, if applicable"
  echo "   - oc delete secret gerrit-ssh-keys -n ${short_name}"
  echo "   - oc create secret generic gerrit-ssh-keys -n ${short_name} --from-file=\"id_rsa=/dev/stdin\" <<<\"\$(pass \"${pw_store_path}/id_rsa\")\""
fi

echo "* Update Jenkins credentials. (in Jiro root dir, run: ./jenkins-create-credentials.sh ${project_name})"
echo "* Commit changes to pass repo."


# clean up
popd
rm -rf temp
