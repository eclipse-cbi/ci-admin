#!/usr/bin/env bash

#*******************************************************************************
# Copyright (c) 2023 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Get projects API stats

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

FILTER_ARCHIVED_PROJECTS=true

CACHE_FILE="projects.eclipse.org-api-cache.json"

# fetch API
"${SCRIPT_FOLDER}/fetch_projects_api.sh"

if ${FILTER_ARCHIVED_PROJECTS}; then
  response="$(jq -r '.[] | select(.state!="Archived") | {project_id: .project_id, github_org: .github.org}' < "${CACHE_FILE}")"
else
  response="$(jq -r '.[] | {project_id: .project_id, github_org: .github.org}' < "${CACHE_FILE}")"
fi

no_of_projects="$(jq '.[].project_id' < "${CACHE_FILE}" | wc -l)"
active_projects="$(jq '.[] | select(.state!="Archived")' < "${CACHE_FILE}")"
no_of_active_projects="$(jq '.project_id' <<< "${active_projects}" | wc -l )"
no_of_github_projects="$(jq 'select(.github.org!="" or .github_repos!=[]) | .project_id' <<< "${active_projects}" | wc -l )"
no_of_github_org_projects="$(jq 'select(.github.org!="") | .project_id' <<< "${active_projects}" | wc -l )"
no_of_github_org1_projects="$(jq 'select(.github.org!="" and .github_repos!=[]) | .project_id' <<< "${active_projects}" | wc -l )"
no_of_gitlab_projects="$(jq 'select(.gitlab.project_group!="" or .gitlab_repos!=[]) | .project_id' <<< "${active_projects}" | wc -l )"
no_of_gitlab_pg_projects="$(jq 'select(.gitlab.project_group!="") | .project_id' <<< "${active_projects}" | wc -l )"
no_of_gitlab_pg1_projects="$(jq 'select(.gitlab.project_group!="" and .gitlab_repos!=[]) | .project_id' <<< "${active_projects}" | wc -l )"
no_of_gitlab_pg2_projects="$(jq 'select(.gitlab.project_group=="" and .gitlab_repos!=[]) | .project_id' <<< "${active_projects}" | wc -l )"
no_of_gerrit_projects="$(jq 'select(.gerrit_repos!=[]) | .project_id' <<< "${active_projects}" | wc -l )"
no_of_gerrit_github_projects="$(jq 'select(.gerrit_repos!=[] and .github_repos!=[]) | .project_id' <<< "${active_projects}" | wc -l )"
no_of_gerrit_gitlab_projects="$(jq 'select(.gerrit_repos!=[] and .gitlab_repos!=[]) | .project_id' <<< "${active_projects}" | wc -l )"
echo "Number of projects: ${no_of_projects}"
echo "Number of active projects: ${no_of_active_projects}"
echo
echo "Number of projects that use GitHub: ${no_of_github_projects}"
echo "  Number of projects that use the GitHub org field: ${no_of_github_org_projects}"
echo "  Number of projects that use the GitHub org AND github_repos fields: ${no_of_github_org1_projects}"
echo "Number of projects that use GitLab: ${no_of_gitlab_projects}"
echo "  Number of projects that use the GitLab project group field: ${no_of_gitlab_pg_projects}"
echo "  Number of projects that use the GitLab project group AND gitlab_repos fields: ${no_of_gitlab_pg1_projects}"
echo "  Number of projects that use ONLY the gitlab_repos fields: ${no_of_gitlab_pg2_projects}"
echo "Number of projects that use Gerrit: ${no_of_gerrit_projects}"
echo "  Number of projects that use Gerrit and GitHub: ${no_of_gerrit_github_projects}"
echo "  Number of projects that use Gerrit and GitLab: ${no_of_gerrit_gitlab_projects}"

#echo "${response}" | jq -r '. | select(.github_org!="") | .project_id'
echo
echo

counter=0
echo "Projects that use Gerrit and have a Jenkins instance:"
for gp in $(jq -r 'select(.gerrit_repos!=[]) | .project_id' <<< "${active_projects}"); do
  if [[ -d "$HOME/git/jiro/instances/${gp}" ]]; then
    echo "- ${gp}"
    counter=$((counter +1))
  fi
done
echo "Found ${counter} projects."

echo
echo "Projects that use Gerrit and GitHub:"
for p in $(jq -r 'select(.gerrit_repos!=[] and .github.org!="") | .project_id' <<< "${active_projects}"); do
#for p in $(jq -r 'select(.gerrit_repos!=[] and .github_repos!=[]) | .project_id' <<< "${active_projects}"); do
  echo "- https://projects.eclipse.org/projects/${p}/edit"
done

echo
echo "Projects that use Gerrit and GitLab:"
for p in $(jq -r 'select(.gerrit_repos!=[] and .gitlab_repos!=[]) | .project_id' <<< "${active_projects}"); do
  echo "- https://projects.eclipse.org/projects/${p}/edit"
done

echo
echo "Projects that only use GitLab repo fields:"
for p in $(jq -r 'select(.gitlab.project_group=="" and .gitlab_repos!=[]) | .project_id' <<< "${active_projects}"); do
  echo "- https://projects.eclipse.org/projects/${p}/edit"
done

