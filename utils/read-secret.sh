#! /usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2018 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

################### This section not specific to this program ###################
# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'
########################### End of the generic section ##########################

from="${1:-"-"}"
timeout_sec="${2:-5}"

set +o errexit
timeout ${timeout_sec} head -n 1 "${from}"
if [[ $? -eq 124 ]]; then
  if [[ "${from}" == "-" ]]; then
    >&2 echo "ERROR: timeout while reading secret from stdin"
  else
    >&2 echo "ERROR: timeout while reading secret from '${from}'"
  fi
  exit 1
fi
set -o errexit