#! /usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2018 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Generates a secure password of the length specified as a parameter. Default is 32 char
pwgen() {
	local length="${1:-32}"
	if hash pwgen 2>/dev/null; then
    "$(which pwgen)" -1 -s -y "${length}"
  else
    head /dev/urandom | tr -dc 'A-Za-z0-9!"#$%&'\''()*+,-./:;<=>?@[\]^_`{|}~' | head -c "${length}" ; echo 
  fi
}
