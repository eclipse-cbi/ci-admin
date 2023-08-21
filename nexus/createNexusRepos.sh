#!/usr/bin/env bash

#*******************************************************************************
# Copyright (c) 2020 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# This script creates "releases" and "snapshots" repos plus a group on the Nexus server

# Requirements:
# * This script relies on credentials for Nexus being set in a .netrc file in your $HOME dir
#   e.g.
#      machine repo.eclipse.org
#        login <username>
#        password <password>

#TODO: check if repo already exists

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
project_shortname="${1:-}"

rest_api_base_url="http://repo.eclipse.org/service/local"

usage() {
  printf "Usage: %s project_shortname\n" "${SCRIPT_NAME}"
  printf "\t%-16s project short name (e.g. cbi for CBI project).\n" "project_name"
}

# check that project short name is not empty
if [[ -z "${project_shortname}" ]]; then
  printf "ERROR: a project short name must be given.\n"
  usage
  exit 1
fi

# check that project name does not contain a dot
if [[ "${project_shortname}" == *.* ]]; then
  printf "ERROR: the project short name should not contain a dot.\n"
  exit 1
fi

nexus_curl() {
    local json="${1:-}"
    local rest_url="${2:-}"
    local method="${3:-}"

    #debug -v -trace-ascii
    if [[ "${method}" == "GET" ]]; then
        response=$(curl -L -s --netrc -H "Accept: application/json" -H "Content-Type: application/json" -X "${method}" "${rest_url}")
    else
        response=$(curl -L -s --netrc -H "Accept: application/json" -H "Content-Type: application/json" -X "${method}" -d "${json}" "${rest_url}")
    fi

    if [[ "${response}" == *"errors"* ]]; then
        error_msg=$(echo "${response}" | jq -M '."errors"[0].msg')
        echo "ERROR: ${error_msg}" >&2
        exit 1
    fi

    if [[ "${method}" == "GET" ]]; then
        echo "${response}"
    fi
}

createRepo () {
    local repo_id="${1:-}"
    local repo_policy="${2:-}"
    local write_policy="ALLOW_WRITE_ONCE"
    if [[ "${repo_policy}" == "SNAPSHOT" ]]; then
      write_policy="ALLOW_WRITE"
    fi
    echo "Creating Nexus repo '${repo_id}'..."
    local json="{\"data\":{\"repoType\": \"hosted\", \"id\": \"${repo_id}\", \"name\": \"${repo_id}\", \"writePolicy\": \"${write_policy}\", \"browseable\": true, \"indexable\": true, \"exposed\": true, \"notFoundCacheTTL\": 1440, \"repoPolicy\": \"${repo_policy}\", \"provider\": \"maven2\", \"providerRole\": \"org.sonatype.nexus.proxy.repository.Repository\", \"downloadRemoteIndexes\": false, \"checksumPolicy\": \"IGNORE\" }}"
    nexus_curl "${json}" "${rest_api_base_url}/repositories" "POST"
}

createGroupRepo () {
    local repo_id="${1:-}"
    echo "Creating Nexus group repo '${repo_id}' with the following repos:"
    echo "* ${repo_id}-releases"
    echo "* ${repo_id}-snapshots"
    local json="{\"data\":{\"id\":\"${repo_id}\",\"name\":\"${repo_id}\",\"format\":\"maven2\",\"exposed\":true,\"provider\":\"maven2\",\"repositories\":[{\"id\":\"${repo_id}-releases\"},{\"id\":\"${repo_id}-snapshots\"}]}}"
    nexus_curl "${json}" "${rest_api_base_url}/repo_groups" "POST"
}

addRepoToGroupRepo() {
    local repo_id="${1:-}"
    local group_id="${2:-}"
    echo "Adding repo '${repo_id}' to group repo '${group_id}'..."

    # get existing repos
    json_old=$(nexus_curl "" "${rest_api_base_url}/repo_groups/${group_id}" "GET")
    # add new repo
    json=$(echo "${json_old}" | jq ".data.repositories += [{\"id\": \"${repo_id}\", \"name\": \"${repo_id}\", \"resourceURI\": \"https://repo.eclipse.org/service/local/repo_groups/releases/${repo_id}\"}]")
    # update group
    nexus_curl "${json}" "${rest_api_base_url}/repo_groups/${group_id}" "PUT"
}

createBugReply () {
    local repo_id="${1:-}"
    cat << EOF
Helpdesk response template:
------------------------

The following repos were created for ${repo_id}:

group:     https://repo.eclipse.org/content/repositories/${repo_id}/ \\
releases:  https://repo.eclipse.org/content/repositories/${repo_id}-releases/ \\
snapshots: https://repo.eclipse.org/content/repositories/${repo_id}-snapshots/

Details on how to use repo.eclipse.org can be found on the wiki at https://wiki.eclipse.org/Services/Nexus and https://wiki.eclipse.org/Jenkins
EOF
}

echo ""
createRepo "${project_shortname}-releases" "RELEASE"
createRepo "${project_shortname}-snapshots" "SNAPSHOT"
createGroupRepo "${project_shortname}"
addRepoToGroupRepo "${project_shortname}-releases" "releases"
addRepoToGroupRepo "${project_shortname}-snapshots" "snapshots"
createBugReply "${project_shortname}"
echo "Done."

