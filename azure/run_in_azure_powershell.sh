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

DOCKER_SCRIPT_NAME="docker_az_ps_script.ps1"
DOCKER_MOUNT_DIR="/test"

## prepare script that is executed in azure-powershell docker image

sp_pw_store_path="IT/CBI/agents/azure/ServicePrincipal"
sp_app_id="$(passw it "${sp_pw_store_path}/app_id")"
sp_password="$(passw it "${sp_pw_store_path}/password")"
sp_tenant_id="$(passw it "${sp_pw_store_path}/tenant_id")"

cat <<EOF > "${DOCKER_SCRIPT_NAME}"
\$sp = New-Object PsObject -Property @{ApplicationID = '${sp_app_id}'; Secret = (ConvertTo-SecureString -String '${sp_password}' -AsPlainText -Force)}
\$pscredential = New-Object -TypeName System.Management.Automation.PSCredential(\$sp.ApplicationID, \$sp.Secret)
Connect-AzAccount -ServicePrincipal -Credential \$pscredential -Tenant '${sp_tenant_id}'

EOF

help() {
  printf "Available commands:\n"
  printf "Command\t\tDescription\n\n"
  printf "run_in_docker\t\tRun command in Azure Powershell.\n"
  printf "run_in_vm\t\tRun Powershell script in Azure VM.\n"
  exit 0
}

run_in_docker() {
  local command="${1:-}"
  echo -e "${command}" >> "${DOCKER_SCRIPT_NAME}"
}

run_in_vm() {
  local agent_name="${1:-}"
  local resource_group="${2:-}"
  local inner_script_name="${3:-}"

  if [ "${agent_name}" == "" ]; then
    printf "ERROR: an agent name must be given.\n"
    exit 1
  fi

  if [ "${resource_group}" == "" ]; then
    printf "ERROR: a resource group must be given.\n"
    exit 1
  fi

  if [ "${inner_script_name}" == "" ]; then
    printf "ERROR: a script name must be given.\n"
    exit 1
  fi

  cat <<EOF >> "${DOCKER_SCRIPT_NAME}"
# Show the output of the command
\$output = Invoke-AzVMRunCommand -ResourceGroupName '${resource_group}' -VMName '${agent_name}' -CommandId 'RunPowerShellScript' -ScriptPath '${DOCKER_MOUNT_DIR}/${inner_script_name}'
Write-Output \$output
foreach (\$v in \$output.Value) {
  Write-Output \$v
}
EOF
}


"$@"

# show help menu, if no first parameter is given
if [[ -z "${1:-}" ]]; then
  help
fi

## Debugging
#printf "\nAzure PowerShell script to be executed in Docker image:\n\n"
#cat "${DOCKER_SCRIPT_NAME}"

## run script in azure-powershell docker image
docker run --rm -v "$(pwd)":${DOCKER_MOUNT_DIR} mcr.microsoft.com/azure-powershell pwsh ${DOCKER_MOUNT_DIR}/${DOCKER_SCRIPT_NAME}

rm -f "${DOCKER_SCRIPT_NAME}"