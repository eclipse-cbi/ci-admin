#!/bin/bash
#*******************************************************************************
# Copyright (c) 2018 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Common functions that are used by all add_creds_* scripts

usage() {
  printf "Usage: %s project_name\n" "$script_name"
  printf "\t%-16s project name (e.g. technology.cbi for CBI project).\n" "project_name"
}

verify_inputs() {
  # check that project name is not empty
  if [ "$project_name" == "" ]; then
    printf "ERROR: a project name must be given.\n"
    usage
    exit 1
  fi

  # check that project name contains a dot
  if [[ "$project_name" != *.* ]]; then
    printf "ERROR: the full project name with a dot must be given (e.g. technology.cbi).\n"
    usage
    exit 1
  fi
}

check_pw_does_not_exists() {
  # check that the entries do not exist yet
  pass ${pw_store_path} &> /dev/null
  if [[ $? == "0" ]]; then
    printf "ERROR: ${site_name} credentials for ${project_name} already exist.\n"
    exit 1
  fi
}

show_info() {
  printf "Project name: ${project_name}\n"
  printf "Short name: ${short_name}\n"
  printf "${site_name} email: ${email}\n"
  printf "${site_name} user: ${user}\n"
}

create_pw() {
  read -p "Do you want to generate the password? (Y)es, (N)ooo, E(x)it: " yn
  case $yn in
    [Yy]* ) pw=$(pwgen -1 -s -y 24);printf "%s password: %s\n" ${site_name} ${pw};;
    [Nn]* ) echo -n "${site_name} password: ";read -r pw;;
    [Xx]* ) exit;;
        * ) echo "Please answer (Y)es, (N)ooo, E(x)it";;
  esac
}

generate_ssh_keys() {
  pwgen -1 -s -y 64 | pass insert -m ${pw_store_path}/id_rsa.passphrase
  pass ${pw_store_path}/id_rsa.passphrase | ./ssh-keygen-ni.sh -C "${email}" -f ${temp_path}

  # Insert private and public key into pw store
  cat ${temp_path} | pass insert -m ${pw_store_path}/id_rsa
  cat ${temp_path}.pub | pass insert -m ${pw_store_path}/id_rsa.pub
  rm ${temp_path}*
}

add_to_pw_store() {
  echo ${email} | pass insert --echo ${pw_store_path}/email
  echo ${pw} | pass insert --echo ${pw_store_path}/password
  echo ${user} | pass insert --echo ${pw_store_path}/username
}