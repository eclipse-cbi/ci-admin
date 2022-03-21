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

source ../pass/pass_wrapper.sh

project_name="${1:-}"
agent_name="${2:-}"
resource_group="${3:-cbi-build-agents}"                   # name of the resource group in Azure


if [ "${project_name}" == "" ]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

if [ "${agent_name}" == "" ]; then
  printf "ERROR: an agent name must be given.\n"
  exit 1
fi

if [ "${resource_group}" == "" ]; then
  printf "ERROR: a resoure group must be given.\n"
  exit 1
fi

short_name="${project_name##*.}"

site="agents/azure/${agent_name}"
pw_store_path="bots/${project_name}/${site}"

script_name="vm_script.ps1"

## prepare script that is executed in VM

#add username to pass, if it does not exist already
if passw cbi "${pw_store_path}/username" 2&>/dev/null ; then
  user="$(passw cbi "${pw_store_path}/username")"
  echo "Found ${pw_store_path}/username."
else
  user="genie.${short_name}"
  echo "${user}" | passw cbi insert --echo "${pw_store_path}/username"
fi

# generate password and add it to pass, if it does not exist already
if passw cbi "${pw_store_path}/password" 2&>/dev/null ; then
  pw="$(passw cbi "${pw_store_path}/password")"
  echo "Found ${pw_store_path}/password."
else
  # exclude brackets and single quotes from passwords
  pw="$(pwgen -s -y 24 -r {}\')"
  echo "${pw}" | passw cbi insert --echo "${pw_store_path}/password"
fi

cat <<EOF > "${script_name}"
\$secret = (ConvertTo-SecureString -String '${pw}' -AsPlainText -Force)
New-LocalUser -Name "${user}" -Password \$secret -PasswordNeverExpires -UserMayNotChangePassword
Add-LocalGroupMember -Group "Remote Desktop Users" -Member "${user}"
EOF

## Debugging
#printf "\nPowerShell script to be executed on VM:\n\n"
#cat "${script_name}"

./run_in_azure_powershell.sh "run_in_vm" "${agent_name}" "${resource_group}" "${script_name}"

rm -f "${script_name}"
