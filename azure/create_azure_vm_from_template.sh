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

TEMPLATE_DIR="templates"
PARAMETERS_FILE="${TEMPLATE_DIR}/parameters.json"
DOCKER_MOUNT_DIR="/test"

agent_name="${1:-}"
template_file="${2:-}"
resource_group="${3:-cbi-build-agents}"                   # name of the resource group in Azure

# parameters with default values
admin_username="${4:-webmaster}"
location="${5:-eastus}"
machine_size="${6:-Standard_B4ms}"
disk_type="${7:-Premium_LRS}"

subscription="$(passw it IT/CBI/agents/azure/subscription)"

if [ "${agent_name}" == "" ]; then
  printf "ERROR: an agent name must be given.\n"
  exit 1
fi

if [ "${template_file}" == "" ]; then
  printf "ERROR: a template file must be given.\n"
  exit 1
fi

if [[ ! -f "${template_file}" ]]; then
  printf "ERROR: template file %s does not exist.\n" "${template_file}"
  exit 1
fi

if [ "${resource_group}" == "" ]; then
  printf "ERROR: a resource group must be given.\n"
  exit 1
fi

pw_store_path="IT/CBI/agents/azure/${agent_name}"
pw_store_path_admin="${pw_store_path}/users/${admin_username}"

#add username to pass, if it does not exist already
if passw it "${pw_store_path_admin}" 2&>/dev/null ; then
  echo "Found ${pw_store_path_admin}."
  admin_pw="$(passw it "${pw_store_path_admin}")"
else
  # generate password and add it to pass
  # exclude brackets and single quotes from passwords
  admin_pw="$(pwgen -s -y 24 -r {}\')"
  echo "${admin_pw}" | passw it insert --echo "${pw_store_path_admin}"
fi


create_parameters_file() {
  local agent_name="${1:-}"
  local resource_group="${2:-}"
  local admin_username="${3:-}"
  local admin_pw="${4:-}"
  local location="${5:-}"
  local machine_size="${6:-}"
  local disk_type="${7:-}"
  local subscription="${8:-}"

  cat <<EOF > "${PARAMETERS_FILE}"
{
    "\$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "location": {
            "value": "${location}"
        },
        "networkInterfaceName": {
            "value": "${agent_name}366"
        },
        "networkSecurityGroupName": {
            "value": "${agent_name}-nsg"
        },
        "networkSecurityGroupRules": {
            "value": [
                {
                    "name": "RDP",
                    "properties": {
                        "priority": 300,
                        "protocol": "TCP",
                        "access": "Allow",
                        "direction": "Inbound",
                        "sourceAddressPrefix": "*",
                        "sourcePortRange": "*",
                        "destinationAddressPrefix": "*",
                        "destinationPortRange": "3389"
                    }
                }
            ]
        },
        "subnetName": {
            "value": "default"
        },
        "virtualNetworkId": {
            "value": "/subscriptions/${subscription}/resourceGroups/${resource_group}/providers/Microsoft.Network/virtualNetworks/${resource_group}-vnet"
        },
        "publicIpAddressName": {
            "value": "${agent_name}-ip"
        },
        "publicIpAddressType": {
            "value": "Dynamic"
        },
        "publicIpAddressSku": {
            "value": "Basic"
        },
        "virtualMachineName": {
            "value": "${agent_name}"
        },
        "virtualMachineComputerName": {
            "value": "${agent_name}"
        },
        "virtualMachineRG": {
            "value": "${resource_group}"
        },
        "osDiskType": {
            "value": "${disk_type}"
        },
        "virtualMachineSize": {
            "value": "${machine_size}"
        },
        "adminUsername": {
            "value": "${admin_username}"
        },
        "adminPassword": {
            "value": "${admin_pw}"
        },
        "patchMode": {
            "value": "Manual"
        },
        "enableHotpatching": {
            "value": false
        }
    }
}
EOF
}

get_public_ip() {
  local agent_name="${1:-}"
  # Get public IP address and add it to pass
  local public_ip
  public_ip="$(./run_in_azure_powershell.sh run_in_docker "Get-AzPublicIpAddress -Name ${agent_name}-ip" | grep '^IpAddress')"
  public_ip="${public_ip##*: }"
  echo "Public IP of agent ${agent_name}: ${public_ip}"

  #TODO: better sanity check
  if [[ ! -z "${public_ip}" ]]; then
    echo "${public_ip}" | passw it insert --echo "${pw_store_path}/ip"
  else
    echo "Public IP was empty."
  fi
}

wait_for_vm() {
  local agent_name="${1:-}"
  local resource_group="${2:-}"

  echo "Checking if VM ${agent_name} is running..."
  # wait 5 times 30 seconds
  for n in {1..6}
  do
    if [[ "${n}" -eq 6 ]]; then
      echo "VM is not running yet. Please investigate."
      exit 1
    fi
    if ./run_in_azure_powershell.sh "run_in_docker" "\$VMDetail = Get-AzVM -ResourceGroupName '${resource_group}' -VMName '${agent_name}' -Status; Write-Output \$VMDetail.Statuses[1].DisplayStatus" | grep "VM running" > /dev/null; then
      echo "VM is running."
      break
    else
      echo "VM is not running yet. Sleeping for 30 seconds (${n}/5)... "
      sleep 30
    fi
  done
}

create_parameters_file "${agent_name}" "${resource_group}" "${admin_username}" "${admin_pw}" "${location}" "${machine_size}" "${disk_type}" "${subscription}"

#TODO: pass adminUsername and adminPassword as inline parameters?
create_vm_command="New-AzResourceGroupDeployment -Name NewDeployment-${agent_name} -ResourceGroupName ${resource_group} -TemplateFile ${DOCKER_MOUNT_DIR}/${template_file} -TemplateParameterFile ${DOCKER_MOUNT_DIR}/${PARAMETERS_FILE}"
./run_in_azure_powershell.sh "run_in_docker" "${create_vm_command}"

# get public IP of VM and add it to pass
get_public_ip "${agent_name}"

# wait for VM to be running
wait_for_vm "${agent_name}" "${resource_group}"

# IMPORTANT!
rm -f ${PARAMETERS_FILE}