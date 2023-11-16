#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2023 Eclipse Foundation and others.
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
PASSWORD_STORE_DIR="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "cbi-dir" "password-store")"

bot_counter=0
gh_counter=0
gl_counter=0
twofa_gh_counter=0
ssh_gh_counter=0
# print only file name: -printf "%f\n"
for folder in $(find "${PASSWORD_STORE_DIR}/bots/" -maxdepth 1 -type d  | sort); do
  b="$(basename "${folder}")"
  if [[ -d "${folder}/github.com" ]]; then
    gh_counter="$((gh_counter+1))"
    if [[ ! -f "${folder}/github.com/2FA-seed.gpg" ]]; then
      echo "2FA is missing for project: ${b}"
      twofa_gh_counter="$((twofa_gh_counter+1))"
    fi
    if [[ ! -f "${folder}/github.com/id_rsa.gpg" ]]; then
      echo "SSH keys are missing for project: ${b}"
      ssh_gh_counter="$((ssh_gh_counter+1))"
    fi
  elif [[ -d "${folder}/gitlab.eclipse.org" ]]; then
    gl_counter="$((gl_counter+1))"
  fi
  bot_counter="$((bot_counter+1))"
done

echo
echo
echo "Number of projects ${bot_counter}"
echo "Number of projects with GitHub bot account ${gh_counter}"
echo "  Number of projects without GitHub bot 2FA: ${twofa_gh_counter}"
echo "  Number of projects without GitHub bot SSH: ${ssh_gh_counter}"
echo "Number of projects with GitLab bot account ${gl_counter}"

