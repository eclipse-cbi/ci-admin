#! /usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2018 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Creates a settings-security maven file and print it on the stdout

################### This section not specific to this program ###################
# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

# Need enhanced getopt (-use ! and PIPESTATUS to get exit code with 'errexit' set)
! getopt --test > /dev/null 
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
  >&2 echo "ERROR: this program requires a enhanced version of getopt."
  exit 1
fi

# Need readlink
if ! command -v readlink > /dev/null; then
  >&2 echo "ERROR: this program requires 'readlink'"
  exit 1
fi

SCRIPT_FOLDER="$(dirname $(readlink -f "${0}"))"
SCRIPT_NAME="$(basename $(readlink -f "${0}"))"
########################### End of the generic section ##########################

# Need mvn
if ! command -v mvn > /dev/null; then
  >&2 echo "ERROR: this program requires 'mvn'"
  exit 1
fi

usage() {
  local b="\033[1m"
  local u="\033[4m"
  local r="\033[0m"
  printf "${b}NAME${r}\n"
  printf "    ${b}%s${r} -- A generator of Maven settings-security.xml file\n\n" "${SCRIPT_NAME}"
  printf "${b}SYNOPSIS${r}\n"
  printf "    ${b}%s${r} [${u}OPTION${r}]...\n\n" "${SCRIPT_NAME}"
  printf "${b}DESCRIPTION${r}\n"
  printf "    ${b}%s${r} is a generator of ${u}settings-security.xml${r} maven file. See ${u}https://maven.apache.org/guides/mini/guide-encryption.html${r} for further information about ${u}settings-security.xml${r} files.\n\n" "${SCRIPT_NAME}"
  printf "    ${b}-b${r} ${u}bits${r}\n"
  printf "        Specifies the number of bits in the key to create. See ${b}ssh-keygen${r} documentation on your system to know supported values. Default value is ${b}4096${r}, but it may be unsupported on your system.\n\n"
  printf "    ${b}-C${r} ${u}comment${r}\n"
  printf "        Provides a new comment. Note that this wrapper provides an empty string as default value, so the comment of the generated will be empty if not specified. This is different from the default behavior of ${b}ssh-keygen${r} which to use '\${USER}@\${HOSTNAME}' as the default value.\n\n"
  printf "    ${b}-f${r} ${u}output_keyfile${r}\n"
  printf "        Specifies the output_keyfile of the key file. Default value is ${b}id_rsa${r}.\n\n"
  printf "    ${b}-P${r} ${u}passphrase_file${r}\n"
  printf "        Specifies the passphrase_file into which the passphrase is stored. If not specified or set to ${b}-${r}, the passphrase is read from the standard input.\n\n"
  printf "    ${b}-t${r} ${u}key_type${r}\n" 
  printf "        Specifies the type of key to create. See ${b}ssh-keygen${r} documentation on your system to know the possible values. Default value is ${b}rsa${r}, but it may be unsupported on your system.\n\n"
  printf "    ${b}-h${r}, ${b}--help${r}\n"
  printf "        print this help and exit.\n\n"
  printf "    ${b}-v${r}, ${b}--verbose${r}\n"
  printf "        Verbose mode. Causes ${b}%s${r} to print messages about its progress.\n\n" ${SCRIPT_NAME}
  printf "    ${b}--debug${r}\n"
  printf "        Debug mode. Causes ${b}%s${r} to print debugging messages about its progress.\n\n" ${SCRIPT_NAME}
}

OPTIONS=p:hv
LONGOPTS=help,verbose,debug

! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
  echo "ERROR: an error occured while parsing the program arguments"
  echo "${PARSED}"
  usage
  exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

# parameter default values
master_password_file="-"
printHelp="n"
verbose="n"
debug="n"

# now enjoy the options in order and nicely split until we see --
while true; do
    case "$1" in
        -p)
            master_password_file="${2}"
            shift 2
            ;;
        -h|--help)
            printHelp="y"
            shift
            ;;
        -v|--verbose)
            verbose="y"
            shift
            ;;
        --debug)
            debug="y"
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "ERROR: an error occured while reading the program arguments (programming error)."
            usage
            exit 3
            ;;
    esac
done

if [[ "${debug}" = "y" ]]; then 
    printf "Program parameters:\n"
    printf "\t%s=%s\n" "bits" ${bits}
    printf "\t%s=%s\n" "comment" ${comment}
    printf "\t%s=%s\n" "key_type" ${key_type}
    printf "\t%s=%s\n" "output_keyfile" ${output_keyfile}
    printf "\t%s=%s\n" "master_password_file" ${master_password_file}
    printf "\t%s=%s\n" "printHelp" ${printHelp}
    printf "\t%s=%s\n" "verbose" ${verbose}
fi

if [[ "${printHelp}" = "y" ]]; then
  usage
  exit 0
fi 

if [[ ! -f "${master_password_file}" ]] && [[ "${master_password_file}" != "-" ]]; then
    echo "ERROR: the specified passphrase file '${master_password_file}' does not exists"
fi

if [[ "${verbose}" = "y" ]]; then 
    echo "Reading passphrase from '${master_password_file}'..."
fi

master_password=$(${SCRIPT_FOLDER}/../utils/read-secret.sh "${master_password_file}")

cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<settingsSecurity>
  <master>$(mvn --encrypt-master-password "${master_password}")</master>
</settingsSecurity>
EOF