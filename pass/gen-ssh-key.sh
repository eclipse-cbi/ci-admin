#! /usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2018 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Generates a new SSH keypair in batch-mode and adds it to pass

################### This section not specific to this program ###################
# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

# Need enhanced getopt (-use ! and PIPESTATUS to get exit code with 'errexit' set)
! getopt --test > /dev/null 
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
  >&2 echo "ERROR: this program requires a enhanced version of 'getopt'"
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

. "${SCRIPT_FOLDER}/sanity-check.sh"

usage() {
  local b="\033[1m"
  local u="\033[4m"
  local r="\033[0m"
  >&2 printf "${b}NAME${r}\n"
  >&2 printf "    ${b}%s${r} -- Generates a new SSH keypair and adds it to pass\n\n" "${SCRIPT_NAME}"
  >&2 printf "${b}SYNOPSIS${r}\n"
  >&2 printf "    ${b}%s${r} [${u}OPTION${r}] [${u}pass-name${r}]...\n\n" "${SCRIPT_NAME}"
  >&2 printf "${b}DESCRIPTION${r}\n"
  >&2 printf "    ${b}%s${r} generates a SSH keypair non-interactively and insert the public key, the private key and the passphrase in pass with the given ${u}pass-name${r} (e.g. bots/technology.cbi/git.eclipse.org).\n\n" "${SCRIPT_NAME}"
  >&2 printf "    ${b}-C${r} ${u}comment${r}, ${b}--comment${r} ${u}comment${r}\n"
  >&2 printf "        Provides a new comment for the SSH key.\n\n"
  >&2 printf "    ${b}-P${r} ${u}passphrase_file${r}\n"
  >&2 printf "        Specifies the passphrase_file into which the passphrase of the key is stored. If not specified or set to ${b}-${r}, the passphrase is read from the standard input.\n\n"
  >&2 printf "    ${b}-f${r}, ${u}--force${r}\n"
  >&2 printf "        If not specified and a SSH key already exists in pass with the given ${u}pass-name${r}, the program failed. Use this option to force overwriting existing key.\n\n"
  >&2 printf "    ${b}-h${r}, ${b}--help${r}\n"
  >&2 printf "        print this help and exit.\n\n"
  >&2 printf "    ${b}-v${r}, ${b}--verbose${r}\n"
  >&2 printf "        Verbose mode. Causes ${b}%s${r} to print messages about its progress.\n\n" ${SCRIPT_NAME}
  >&2 printf "    ${b}--debug${r}\n"
  >&2 printf "        Debug mode. Causes ${b}%s${r} to print debugging messages about its progress.\n\n" ${SCRIPT_NAME}
}

OPTIONS=C:P:fhv
LONGOPTS=comment:,force,help,verbose,debug

! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
  >&2 echo "ERROR: an error occured while parsing the program arguments"
  >&2 echo "${PARSED}"
  usage
  exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

# parameter default values
passname=""
comment=""
passphrase_file="-"
force="n"
printHelp="n"
verbose="n"
debug="n"

# now enjoy the options in order and nicely split until we see --
while true; do
    case "$1" in
        -C|--comment)
            comment="${2}"
            shift 2
            ;;
        -P)
            passphrase_file="${2}"
            shift 2
            ;;
        -f|--force)
            force="y"
            shift
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
            >&2 echo "ERROR: an error occured while reading the program arguments (programming error)."
            usage
            exit 3
            ;;
    esac
done

if [[ "${printHelp}" = "y" ]]; then
  usage
  exit 0
fi 

passname="${1:-}"
if [[ -z "${passname}" ]]; then
  >&2 echo "ERROR: missing password store path argument"
  usage
  exit 1
fi

if [[ "${debug}" = "y" ]]; then 
    printf "Program parameters:\n"
    printf "\t%s=%s\n" "passname" ${passname}
    printf "\t%s=%s\n" "comment" ${comment}
    printf "\t%s=%s\n" "passphrase_file" ${passphrase_file}
    printf "\t%s=%s\n" "force" ${force}
    printf "\t%s=%s\n" "printHelp" ${printHelp}
    printf "\t%s=%s\n" "verbose" ${verbose}
fi

if [[ ! -f "${passphrase_file}" ]] && [[ "${passphrase_file}" != "-" ]]; then
    >&2 echo "ERROR: the specified passphrase file '${passphrase_file}' does not exists"
    exit 1
fi

key="$(mktemp -t id_rsa.XXXXXXXXXX)"
rm "${key}"
pass_options=""
if pass ${passname}/id_rsa &> /dev/null || ${passname}/id_rsa.pub &> /dev/null || ${passname}/id_rsa.passphrase &> /dev/null; then
  if [[ "${force}" == "n" ]]; then 
    >&2 echo "ERROR: ssh key (or part of) already exist in password store at given path '${passname}'"
    >&2 pass ${passname}
    exit 1
  else
    >&2 echo "WARNING: ssh key (or part of) already exist in password store at given path and will be overridden '${passname}'"
    pass_options="-f"
  fi
fi

if [[ "${verbose}" = "y" ]]; then 
    >&2 echo "Reading passphrase from '${passphrase_file}'..."
fi

passphrase=$(${SCRIPT_FOLDER}/../utils/read-secret.sh "${passphrase_file}")

if [[ "${debug}" = "y" ]]; then 
    >&2 printf "Read passphrase=%s\n" ${passphrase}
fi

./ssh-keygen-ni.sh -C "${comment}" -f "${key}" <<< "${passphrase}"

pass insert -m ${pass_options} ${passname}/id_rsa.passphrase <<< "${passphrase}" > /dev/null
cat "${key}" | pass insert -m ${pass_options} ${passname}/id_rsa > /dev/null
cat "${key}.pub" | pass insert -m ${pass_options} ${passname}/id_rsa.pub > /dev/null

rm -f "${key}"*