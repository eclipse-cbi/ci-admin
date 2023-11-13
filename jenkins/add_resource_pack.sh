#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2022 Eclipse Foundation and others.
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

SCRIPT_FOLDER="$(dirname "$(readlink -f "${0}")")"

PROJECT_NAME="${1:-}"
RESOURCE_PACKS="${2:-}"
DEDICATED_AGENTS="${3:-}"
SPONSOR_NAME="${4:-}"
TICKET_URL="${5:-}"
COMMENT="${6:-}"

if [ -z "${PROJECT_NAME}" ]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

if [ -z "${RESOURCE_PACKS}" ]; then
  printf "ERROR: Number of resource packs must be given.\n"
  exit 1
fi

if [[ "${RESOURCE_PACKS}" -lt 0 ]]; then
  echo "Number of resource packs must be 0 or greater..."
  exit 1
fi

if [ -z "${DEDICATED_AGENTS}" ]; then
  printf "ERROR: Number of dedicated agents must be given.\n"
  exit 1
fi

if [[ "${DEDICATED_AGENTS}" -lt 0 ]]; then
  echo "Number of dedicated agents must be 0 or greater..."
  exit 1
fi

if [ -z "${SPONSOR_NAME}" ]; then
  printf "ERROR: a sponsor name must be given.\n"
  exit 1
fi

if [ -z "${TICKET_URL}" ]; then
  printf "ERROR: a ticket url must be given.\n"
  exit 1
fi

#COMMENT is optional

JIRO_ROOT_FOLDER="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "jiro-root-dir")"
CBI_SPONSORSHIPS_API_ROOT_DIR="$("${SCRIPT_FOLDER}/../utils/local_config.sh" "get_var" "cbi-sponsorships-api-root-dir")"

check_avail() {
  local resource="${1:-}"
  local resource_text="${2:-}"
  # check whether dedicated agents are available => cbi-sponsorships-api
  avail="$("${CBI_SPONSORSHIPS_API_ROOT_DIR}/checkStats.sh" "${SPONSOR_NAME}" "${resource}")"
  rp="$((avail - RESOURCE_PACKS))"
  echo
  if [[ "${rp}" -lt 0 ]]; then
    echo "ERROR: Sponsor '${SPONSOR_NAME}' does not have enough ${resource_text} left!"
    exit 1
  else
    echo "Sponsor '${SPONSOR_NAME}' has enough ${resource_text} available! (${avail} left before assignment)"
  fi
}

update_cbi_sponsorship_api() {
  local JSON_FILE="${CBI_SPONSORSHIPS_API_ROOT_DIR}/cbiSponsoredProjects.json"
  local JSON_TEMP_FILE="${CBI_SPONSORSHIPS_API_ROOT_DIR}/cbiSponsoredProjects_temp.json"
  printf "\nUpdating CBI Sponsorship API...\n"
  # if project_id exist, append or delete sponsoring org
  if jq -e '[.[].project_id] | any(.=="'${PROJECT_NAME}'")' < "${JSON_FILE}" > /dev/null; then
    echo "  Updating existing project entry '${PROJECT_NAME}'..."
    if jq -e '[.[] | select(.project_id=="'${PROJECT_NAME}'") | .sponsoringOrganizations[].name] | any(.=="'${SPONSOR_NAME}'")' < "${JSON_FILE}" > /dev/null; then
      #echo "Update existing sponsoringOrganizations entry '${SPONSOR_NAME}'..."
      echo "  ERROR: Updating existing sponsoringOrganizations entries is not supported yet, please merge manually!"
    else
      echo "  Creating new sponsoringOrganizations entry '${SPONSOR_NAME}'..."
      jq '[.[] | select(.project_id=="'${PROJECT_NAME}'").sponsoringOrganizations += [{
      "name": "'${SPONSOR_NAME}'",
      "resourcePacks": '${RESOURCE_PACKS}',
      "dedicated": '${DEDICATED_AGENTS}',
      "tickets": [
        "'${TICKET_URL}'"
      ],
      "comment": "'${COMMENT}'"
      }]]' < "${JSON_FILE}" > "${JSON_TEMP_FILE}"
    fi
  else
    echo "  Creating new project entry '${PROJECT_NAME}'..."
    jq '. + [{
      "project_id": "'${PROJECT_NAME}'",
      "sponsoringOrganizations": [{
        "name": "'${SPONSOR_NAME}'",
        "resourcePacks": '${RESOURCE_PACKS}',
        "dedicated": '${DEDICATED_AGENTS}',
        "tickets": [
          "'${TICKET_URL}'"
        ],
        "comment": "'${COMMENT}'"
      }]
    }]' < "${JSON_FILE}" > "${JSON_TEMP_FILE}"
  fi
  if [[ -f "${JSON_TEMP_FILE}" ]]; then
    mv "${JSON_TEMP_FILE}" "${JSON_FILE}"
  fi
  #Run build to create /cbi-sponsorships-api/cbiSponsorships.json
  "${CBI_SPONSORSHIPS_API_ROOT_DIR}/build.sh"
}

update_jiro_config() {
  local config_file="${JIRO_ROOT_FOLDER}/instances/${PROJECT_NAME}/config.jsonnet"
  printf "\nUpdating JIRO configuration...\n"
  if [[ ! -f "${config_file}" ]]; then
    echo "  ERROR: JIRO ${config_file} cannot be found."
    exit 1
  fi
  if grep 'resourcePacks' < "${config_file}" > /dev/null; then
    #TODO: simplify?
    original_value="$(grep 'resourcePacks' < "${config_file}" | sed 's/^.*resourcePacks://' | tr -d ' ,')"
    echo "  Found ${original_value} resource packs."
    new_value="$((original_value + RESOURCE_PACKS))"
    sed -i "s/resourcePacks: [0-9]*/resourcePacks: ${new_value}/" "${config_file}"
  else
    echo "  No resource packs defined in JIRO configuration so far."
    new_value="$((1 + RESOURCE_PACKS))"
    new_line="   resourcePacks: ${new_value},"
    #TODO: simplify?
    sed -i "/displayName/a \ ${new_line}" "${config_file}"
  fi
}

"${CBI_SPONSORSHIPS_API_ROOT_DIR}/memberOrganizationsBenefits.sh"
if [[ "${RESOURCE_PACKS}" -gt 0 ]]; then
  check_avail "resourcePacks" "resource packs"
fi
if [[ "${DEDICATED_AGENTS}" -gt 0 ]]; then
  check_avail "dedicatedAgents" "dedicated agents"
fi
update_cbi_sponsorship_api
if [[ "${RESOURCE_PACKS}" -gt 0 ]]; then
  update_jiro_config
else
  echo "INFO: Number of resource packs is lower than 1, skipping update of jiro config."
fi

echo
echo "TODO: commit changes in cbi-sponsoring-api and jiro repos!"
