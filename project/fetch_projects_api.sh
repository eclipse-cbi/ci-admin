#!/usr/bin/env bash

#*******************************************************************************
# Copyright (c) 2023 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Fetch and cache projects.eclipse.org API
# TODO: make cache timeout configurable

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

CACHE_FILE="projects.eclipse.org-api-cache.json"
PAGE_SIZE=100
CACHE_TIMEOUT=14400 # 4 hours
LAST_PAGE="$(curl -sSI "https://projects.eclipse.org/api/projects?pagesize=${PAGE_SIZE}" | grep "link:" | cut -d',' -f4 | sed 's/.*page=//' | sed 's/&.*//')"

# only query API if cache file is older than 1 hour
if [[ ! -f ${CACHE_FILE} ]] || [ "$(stat --format=%Y ${CACHE_FILE})" -le $(( $(date +%s) - CACHE_TIMEOUT )) ]; then
  echo "Cache expired (4 hours). Fetching data from projecst.eclipse.org API..."
  for page in $(seq 1 1 "${LAST_PAGE}"); do
    response="$(curl -sSL "https://projects.eclipse.org/api/projects?pagesize=${PAGE_SIZE}&page=${page}")"
    full_response+="${response}"
  done
  echo "${full_response}" > "${CACHE_FILE}"
fi

#no_of_projects="$(jq .[].short_project_id < ${CACHE_FILE}| wc -l)"
#echo "Found ${no_of_projects} projects."