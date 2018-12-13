#! /usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2018 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Create a new SSH keypair in batch-mode and add it to pass

################### This section not specific to this program ###################
# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

# Need pass
if ! command -v pass > /dev/null; then
  >&2 echo "ERROR: this program requires 'pass'"
  exit 1
fi
########################### End of the generic section ##########################

if [[ -z "${PASSWORD_STORE_DIR+x}" ]]; then
  >&2 echo "ERROR: environment variable PASSWORD_STORE_DIR is not set"
  >&2 echo "You probably use a non default password store directory, so you shall use a command similar to the ones below"
  >&2 echo "    export PASSWORD_STORE_DIR=~/.password-store/subfolder"
  >&2 echo "    export PASSWORD_STORE_DIR=~/.secondary-password-store"
  >&2 echo "If you really want to stick with the default path, you can use one of the commands below"
  >&2 echo "    export PASSWORD_STORE_DIR=\"\""
  >&2 echo "    export PASSWORD_STORE_DIR=~/.password-store"
  exit 2
fi