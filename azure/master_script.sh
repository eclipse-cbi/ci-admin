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
project_name="${2:-}"
template_file="${3:-}"
resource_group="${4:-cbi-build-agents}"                   # name of the resource group in Azure


if [ "${agent_name}" == "" ]; then
  printf "ERROR: an agent name must be given.\n"
  exit 1
fi

if [ "${project_name}" == "" ]; then
  printf "ERROR: a project name must be given.\n"
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

./create_azure_vm_from_template.sh "${agent_name}" "${template_file}" "${resource_group}"

./create_genie_account.sh "${project_name}" "${agent_name}" "${resource_group}"

./setup_azure_vm.sh "${agent_name}"