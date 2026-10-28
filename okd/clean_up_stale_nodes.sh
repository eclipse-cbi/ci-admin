#!/usr/bin/env bash

#*******************************************************************************
# Copyright (c) 2026 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Delete stale nodes from JENKINS_HOME/nodes directories
# TODO: identify legit nodes directories that are still being used and skip them

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

PROJECT_NAME="${1:-}"

# check that project name is not empty
if [[ -z "${PROJECT_NAME}" ]]; then
  printf "ERROR: a project name must be given.\n"
  exit 1
fi

SHORT_NAME="${PROJECT_NAME##*.}"

echo "Counting nodes..."
oc rsh -n "${SHORT_NAME}" "${SHORT_NAME}-0" ls nodes | wc -l
echo "Deleting nodes..."
oc rsh -n "${SHORT_NAME}" "${SHORT_NAME}-0" find nodes/ -mindepth 1 -type d -prune -exec rm -rf {} \; || true
echo "Counting nodes again..."
oc rsh -n "${SHORT_NAME}" "${SHORT_NAME}-0" ls nodes | wc -l

