#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2022 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# This script sets up JDK installations
# Supported:
# * openjdk
# * Temurin
# * IBM Semeru

#TODO: can the <version> variable replacement be simplified??
#TODO: use only a single output file for ALL JDK versions? (must be able to be updated)

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
CI_ADMIN_ROOT="${SCRIPT_FOLDER}/.."
JDK_CONFIG="jdk_config.json"

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.3"

JDK_NAME="${1:-}"

# check that jdk name is not empty
if [[ -z "${JDK_NAME}" ]]; then
  printf "ERROR: a JDK name must be given.\n"
  exit 1
fi

#TODO: check if jdk name exists in jdk_config.json instead of hardcoded list
if [[ "${JDK_NAME}" != "openjdk" ]] && [[ "${JDK_NAME}" != "temurin" ]] && [[ "${JDK_NAME}" != "semeru" ]]; then
  printf "ERROR: only the following JDKs are supported at the moment: 'openjdk', 'temurin' and 'semeru'.\n"
  exit 1
fi


JDK_DISPLAY_NAME="$(jq -r ".${JDK_NAME}[].display_name" "${JDK_CONFIG}")"
API_URL="$(jq -r ".${JDK_NAME}[].url" "${JDK_CONFIG}")"

#echo "${JDK_NAME}"
#echo "${JDK_DISPLAY_NAME}"
#echo "${API_URL}"

OUTPUT_FILE="${SCRIPT_FOLDER}/${JDK_NAME}_jdk_versions.json"
BASE_PATH="/home/data/cbi/buildtools/java/${JDK_NAME}"

backend_user="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "user" "backend_server")"
backend_server="$("${CI_ADMIN_ROOT}/utils/local_config.sh" "get_var" "server" "backend_server")"
CONNECTION="${backend_user}@${backend_server}"

is_ea_build() {
  local version="${1:-}"
  local base_url="https://jdk.java.net/${version}"

  local temp_html="ea.html"
  wget -q -O - "${base_url}" --user-agent="${USER_AGENT}" | tail -n+2 | xmlstarlet format --omit-decl --dropdtd 2>/dev/null > "${temp_html}" || true
  sed -i "s/<html .*>/<html>/" "${temp_html}"

  # if headline includes "Early-Access" consider the version to be an EA
  # if headline includes "Release-Candidate" consider the version to be an RC
  #xmlstarlet sel -t -v "html/body/div/h1" "${temp_html}" | grep -e "Early-Access" > /dev/null
  xmlstarlet sel -t -v "html/body/div/h1" "${temp_html}" | grep -e "Early-Access" -e "Release-Candidate"  > /dev/null
}

#expects that is_ea_build did run before
create_openjdk_ea_array() {
  local version="${1:-}"
  local base_url="https://jdk.java.net/${version}"
  local os="linux-x64_bin"
  local temp_html="ea.html"

  # get download url
  local download_url
  download_url="$(xmlstarlet sel -t -v "html/body/div/blockquote/table/tr/td/a/@href" "${temp_html}" | grep "${os}")"

  # get build number
  local build_number
#TODO: make this more robust
  build_number="$(echo "${download_url}" | sed 's/^.*openjdk-//' | sed 's/_.*$//')"

  #rm -rf "${temp_html}"
  printf "%s\n%s\n" "${build_number}" "${download_url}"
}

create_openjdk_archive_array() {
  local version="${1:-}"
  local base_url="https://jdk.java.net/archive"
  local os="linux-x64_bin"
  local temp_html="archive.html"
#TODO: why is return code != 0?
  wget -q -O - "${base_url}" --user-agent="${USER_AGENT}" | tail -n+2 | xmlstarlet format --omit-decl --dropdtd 2>/dev/null > "${temp_html}" || true
  sed -i "s/<html .*>/<html>/" "${temp_html}"

  # get build number
  local build_number
#TODO: simplify
  build_number="$(xmlstarlet sel -t -v "html/body/div/blockquote/table/tr/th" "${temp_html}" | grep "build" | grep "^${version}" | head -n1 | sed 's/.*build //' | tr -d ')')"

  # get download url
  #TODO: fix xpath and avoid grep
  local download_url
#TODO: simplify
  download_url="$(xmlstarlet sel -t -v "html/body/div/blockquote/table/tr/td/a/@href" "${temp_html}" | grep "${os}" | grep "jdk${version}" | head -n1)"

  #rm -rf "${temp_html}"
  printf "%s\n%s\n" "${build_number}" "${download_url}"
}

create_openjdk_array() {
  local version="${1:-}"
  local base_url="https://jdk.java.net/${version}"
  local os="linux-x64_bin"
  local temp_html="release.html"
#TODO: why is return code != 0?
  wget -q -O - "${base_url}" --user-agent="${USER_AGENT}" | tail -n+2 | xmlstarlet format --omit-decl --dropdtd 2>/dev/null > "${temp_html}" || true
  sed -i "s/<html .*>/<html>/" "${temp_html}"

  # get build number
  local build_number
#TODO: simplify
  build_number="$(xmlstarlet sel -t -v "html/body/div/h1" "${temp_html}" | sed 's/OpenJDK JDK //' | sed 's/ General-Availability Release//')"

  # get download url
  #TODO: fix xpath and avoid grep
  local download_url
#TODO: simplify
  download_url="$(xmlstarlet sel -t -v "html/body/div/blockquote/table/tr/td/a/@href" "${temp_html}" | grep "${os}" | head -n1)"

  #rm -rf "${temp_html}"
  printf "%s\n%s\n" "${build_number}" "${download_url}"
}

get_versions_from_website() {
  echo "Fetching ${JDK_DISPLAY_NAME} versions from website..."
  cat <<EOE > "${OUTPUT_FILE}"
{
  "${JDK_NAME}": [
EOE
  #new JDK versions need to be added in the config file
  local version_array
  version_array=($(jq -r ".${JDK_NAME}[].versions" "${JDK_CONFIG}" | tr -d '[]," '))
  for version in "${version_array[@]}"; do
    echo "  JDK version: ${version}"

    #TODO: find better api for semeru and openjdk or transform/create custom JSON

    if [[ "${JDK_NAME}" != "openjdk" ]]; then
      local api_url
      #api_url="$(echo "${API_URL}" | sed "s/<version>/${version}/")"
      api_url="${API_URL//<version>/${version}}"
      local json
      json="$(curl -sSL -H "Accept: application/json" "${api_url}")"
    fi

    # DEBUG
    #echo "${json}" | jq .

    local release_name
    local build_number
    local download_url

#TODO: try to avoid if condition (use jdk_config.json instead
    if [[ "${JDK_NAME}" == "temurin" ]]; then
      release_name="$(echo "${json}" | jq -r '.[].release_name')"
      # build_number="$(echo "${json}" | jq -r '.[].version.semver')"
      build_number="$(echo "${json}" | jq -r '.[].release_name')"
      download_url="$(echo "${json}" | jq -r '.[].binary.package.link')"
    elif [[ "${JDK_NAME}" == "semeru" ]]; then
      release_name="$(echo "${json}" | jq -r '.name')"
      build_number="$(echo "${release_name}" | sed 's/jdk-//' | sed 's/_openj9.*//')"
      local jq_query=".assets[] | select(.name | contains(\"ibm-semeru-open-jdk_x64_linux\") and endswith(\".tar.gz\")) | .browser_download_url"
      download_url="$(echo "${json}" | jq -r "${jq_query}")"
    elif [[ "${JDK_NAME}" == "openjdk" ]]; then
      if is_ea_build "${version}"; then
        echo "  JDK ${version} is an early access build!"
        #shellcheck disable=SC2046
        readarray -t array <<< $(create_openjdk_ea_array "${version}")
      else
        #shellcheck disable=SC2046
        readarray -t array <<< $(create_openjdk_archive_array "${version}")
        if [[ -z "${array[0]}" ]]; then
          echo "Version ${version} not found on archive page, trying release page..."
          create_openjdk_array "${version}"
          #shellcheck disable=SC2046
          readarray -t array <<< $(create_openjdk_array "${version}")
        fi
      fi
      release_name="${array[0]}"
      build_number="${array[0]}"
      download_url="${array[1]}"
    fi

    echo "  Release name: ${release_name}"
    echo "  Build number: ${build_number}"
    echo "  Download URL: ${download_url}"
    echo
    cat <<EOF >> "${OUTPUT_FILE}"
    {
      "jdk_version": "${version}",
      "url": "${download_url}",
      "name": "${download_url##*/}",
      "build_number": "${build_number}"
    },
EOF
  done

  #remove last comma
  sed -i "$ s/,$//" "${OUTPUT_FILE}"

  cat <<EOG >> "${OUTPUT_FILE}"
  ]
}
EOG
echo
echo
}

get_versions_from_file_server() {
  #shellcheck disable=SC2087
  ssh "${CONNECTION}" /bin/bash << EOF
for file in ${BASE_PATH}/*; do
  if [[ \${file} == *"latest" ]] || [[ \${file} == *"tar.gz" ]]; then
    continue;
  fi
  echo \$(basename \$file | sed "s/jdk-//")
done
EOF
}

update() {
  local version="${1:-}"

  local name
  name="$(jq -r ".${JDK_NAME}[] | select(.jdk_version==\"$version\") | .name"  "${OUTPUT_FILE}")"
  local json_version
  json_version="$(jq -r ".${JDK_NAME}[] | select(.jdk_version==\"$version\") | .build_number"  "${OUTPUT_FILE}")"
  local url
  url="$(jq -r ".${JDK_NAME}[] | select(.jdk_version==\"$version\") | .url" "${OUTPUT_FILE}")"

  echo "name: ${name}"
  echo "json_Version: ${json_version}"
  echo "url: ${url}"
  echo

#TODO: check if dir already exists

  #wget on bambam does not work
  wget -c "${url}" --user-agent="${USER_AGENT}"
  rsync -P -e ssh "${name}" "${CONNECTION}":/tmp/

  #TODO: fails when assigning separately?
  local extraction_dir="$(tar tzf "${name}" | head -1 | cut -f1 -d"/") || true"
  #local extraction_dir="$(tar tzf "${name}" | head -1 | cut -f1 -d"/")"

  local user="outage4"
  local server="bambam"
  local pw="it-pass/IT/accounts/shell/outage4@build,lts,bambam"
  local pwRoot="it-pass/IT/accounts/shell/root@fred,barney,backend"

  local userPrompt="$user@$server:~> *"
  local passwordPrompt="\[Pp\]assword: *"
  local serverRootPrompt="$server:~ # *"

#TODO: check if new jdk is already in place

  # ask if latest-link should be updated
  local update_latest
  update_latest="$(question_update_latest "${version}")"

  expect -c "
  #5 seconds timeout
  set timeout 5

  # ssh to remote
  spawn ssh $user@$server

  expect {
    -re \"$passwordPrompt\" {
      send [exec pass $pw]\r
    }
    #TODO: only works one time
    -re \"passphrase\" {
      interact -o \"\r\" return
    }
  }
  expect -re \"$userPrompt\"

  # su to root
  send \"su -\r\"
  interact -o -nobuffer -re \"$passwordPrompt\" return
  send [exec pass $pwRoot]\r
  expect -re \"$serverRootPrompt\"

  # create dir if it does not exist yet
  send \"mkdir -p ${BASE_PATH}/jdk-${version}\r\"
  # move and extract jdk
  send \"cd ${BASE_PATH}/jdk-${version}\r\"
  #send \"mv /tmp/${name} .\r\"
  send \"cp /tmp/${name} .\r\"
  send \"tar xzf ${name}\r\"

  #TODO: does not work for ea versions (extracted folder is named 'jdk-19' without the ea suffix)
  send \"ls -al\r\"
    #TODO: reliably identify the new dir and set the symlink accordingly
    #TODO: this still needs to be fixed for non-temurin JDKs

  send \"mv ${extraction_dir} ${json_version}\r\"
  send \"ls -al\r\"
  # double-check that dir exists
  if { \"$update_latest\" == \"true\" } {
    send \"ln -sfn ${json_version} latest\r\"
    send \"ls -al latest\r\"
  }
  send \"rm ${name}\r\"

  # exit su, exit su and exit ssh
  send \"exit\rexit\rexit\r\"
  expect eof
"
}

#TODO: replace with question util functions?

question_update_latest() {
  local version="${1:-}"
  read -rp "Do you want to update the latest symlink for JDK ${version}? (Y)es, (N)o, E(x)it: " yn
  case $yn in
    [Yy]* ) echo "true" ;;
    [Nn]* ) echo "false" ;;
    [Xx]* ) exit 0;;
        * ) echo "Please answer (Y)es, (N)o, E(x)it"; question_update_latest "${version}";
  esac
}

question_update() {
  local version="${1:-}"
  read -rp "Do you want to update JDK ${version}? (Y)es, (N)o, E(x)it: " yn
  case $yn in
    [Yy]* ) update "${version}";;
    [Nn]* ) return ;;
    [Xx]* ) exit 0;;
        * ) echo "Please answer (Y)es, (N)o, E(x)it"; question_update "${version}";
  esac
}

is_latest_version() {
  local version="${1:-}"

  # read from json file
  local json_version
  json_version="$(jq -r ".${JDK_NAME}[] | select(.jdk_version==\"$version\") | .build_number"  "${OUTPUT_FILE}")"
  if [[ -z "${json_version}" ]]; then
    echo "  Not found in JSON file. Skipping..."
    return
  fi

  local server_version
  server_version="$(ssh "${CONNECTION}" readlink "${BASE_PATH}/jdk-${version}/latest" || true)"
  echo "server_versioni: ${server_version}"
  if [[ -z "${server_version}" ]]; then
    echo "ERROR: ${BASE_PATH}/jdk-${version}/latest is missing"
#TODO: ask if latest should be created
    exit 1
  fi

  echo "  JSON version:   ${json_version}"
  echo "  Server version: ${server_version}"

  if [[ "${json_version}" == "${server_version}" ]]; then
    echo "  Already latest version installed. Nothing to do!"
  else
    echo "  Newer version available!"
    question_update "${version}"
  fi
}

wiki_text() {
  echo
  echo
  echo "Wiki text for ${JDK_DISPLAY_NAME} JDKs:"
  echo "==========================="
  echo
#TODO: find latest version automatically
  local latest_version
  latest_version="$(jq -r ".${JDK_NAME}[] | select(.jdk_version==\"17\") | .build_number" "${OUTPUT_FILE}" | sed -E 's/jdk-?//')"
  echo "* ${JDK_NAME}-latest <code>/opt/tools/java/${JDK_NAME}/latest</code> = '''${latest_version}'''"

  local version_array=($(jq -r ".${JDK_NAME}[].versions" "${JDK_CONFIG}" | tr -d '[]," '))

#TODO: reverse order
  for version in "${version_array[@]}"; do
    local build_number
    build_number="$(jq -r ".${JDK_NAME}[] | select(.jdk_version==\"$version\") | .build_number" "${OUTPUT_FILE}" | sed -E 's/jdk-?//')"
    echo "* ${JDK_NAME}-jdk${version}-latest <code>/opt/tools/java/${JDK_NAME}/jdk-${version}/latest</code> = '''${build_number}'''"
  done
  echo
}

create_new() {
  # if JDK version does not exist yet, create it (e.g. new ea build)
  local server_side_list
  server_side_list="$(get_versions_from_file_server | sort -n | tr '\n' ' ')"
  local jdk_config_version_list
  jdk_config_version_list=("$(jq -r ".${JDK_NAME}[].versions[]" "${JDK_CONFIG}")")
  for config_version in ${jdk_config_version_list[@]}; do
    if echo "${server_side_list}" | grep -v "${config_version}" > /dev/null; then
      question_update "${config_version}"
    fi
  done
}


# MAIN

#TODO: email template
#TODO: notify when Jenkins templates need to be modified (when a new JDK version is added)

get_versions_from_website

echo "Checking ${JDK_DISPLAY_NAME} versions on server..."
for ver in $(get_versions_from_file_server | sort -n); do
  printf "\n%s %s:\n" "${JDK_DISPLAY_NAME}" "${ver}"
  is_latest_version "${ver}"
done

create_new

wiki_text

#TODO: trap ask to cleanup JDKs
