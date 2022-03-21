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

agent_name="${1:-}"
resource_group="${2:-cbi-build-agents}"   # name of the resource group in Azure

if [ "${agent_name}" == "" ]; then
  printf "ERROR: an agent name must be given.\n"
  exit 1
fi

restart_vm() {
  local agent_name="${1:-}"
  local resource_group="${2:-}"
  local script_name="run_boxstarter_script.ps1"

  ./run_in_azure_powershell.sh "run_in_docker" "Restart-AzVM -Name \"${agent_name}\" -ResourceGroupName \"${resource_group}\""
  echo "Sleeping for 60 seconds while VM restarts..."
  sleep 60
}

install_choco_script() {
  local agent_name="${1:-}"
  local resource_group="${2:-}"
  local script_name="install_choco.ps1"
  ## prepare script that is executed in VM

  cat <<EOF > "${script_name}"
\$output = Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
Write-Output \$output
EOF

  printf "\nPowerShell script to be executed on VM:\n\n"
  cat "${script_name}"

  ./run_in_azure_powershell.sh "run_in_vm" "${agent_name}" "${resource_group}" "${script_name}"

  # Restart VM to properly set environment after chocolatey installation, since refreshenv is not enough
  restart_vm "${agent_name}" "${resource_group}"
}

create_install_script() {
  local agent_name="${1:-}"
  local resource_group="${2:-}"
  local script_name="install_script.ps1"
  local agent_specific_file="agent-scripts/${agent_name}.ps1"

  # Can not include a single quote!!!
  cat <<"EOF" > "${script_name}"
#--- Tools ---
choco install sysinternals -y

#--- Apps ---
choco install googlechrome -y
choco install adoptopenjdk8 -y
choco install adoptopenjdk11 -y
choco install ant -y
choco install maven -y
choco install cygwin -y
choco install cyg-get -y

# choco install tightvnc -y

#--- Cygwin packages ---
cyg-get git wget curl unzip zip unix2dos


EOF

  if [[ -f "${agent_specific_file}" ]]; then
    echo "Found ${agent_specific_file}"
    cat "${agent_specific_file}" >> "${script_name}"
    printf "\n\n" >> "${script_name}"
  else
    echo "No agent specific file found (${agent_specific_file})."
  fi

  printf "\nPowerShell script to be executed on VM:\n\n"
  cat "${script_name}"

  ./run_in_azure_powershell.sh "run_in_vm" "${agent_name}" "${resource_group}" "${script_name}"
}

## MAIN

# Execution time: 1min10sec
install_choco_script "${agent_name}" "${resource_group}"

create_install_script "${agent_name}" "${resource_group}"

#TODO: ./uninstall_packages.sh "${agent_name}" "${resource_group}"

rm -f ./*.ps1