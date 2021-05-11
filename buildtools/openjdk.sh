#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2020 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# This script sets up OpenJDK installations

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'

SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# get jq if not available on system
if ! command -v jq > /dev/null; then
  shopt -s nocasematch
  if [[ $(uname) =~ "darwin" ]]; then
    curl -sSL -z "${SCRIPT_FOLDER}/jq" -o "${SCRIPT_FOLDER}/jq" "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-osx-amd64"
  else
    curl -sSL -z "${SCRIPT_FOLDER}/jq" -o "${SCRIPT_FOLDER}/jq" "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"
  fi
  shopt -u nocasematch

  chmod u+x "${SCRIPT_FOLDER}/jq"
  export PATH="${SCRIPT_FOLDER}:${PATH}"
fi

TARGET="${1:-"."}"

LATEST_RELEASES=$(cat <<EOF
[
  {
    "feature_version": 17,
    "pre": "ea",
    "link": "https://download.java.net/java/early_access/jdk17/21/GPL/openjdk-17-ea+21_linux-x64_bin.tar.gz",
    "name": "openjdk-17-ea+21_linux-x64_bin.tar.gz",
    "openjdk_version": "17-ea+21"
  },
  {
    "feature_version": 16,
    "link": "https://download.java.net/java/GA/jdk16.0.1/7147401fd7354114ac51ef3e1328291f/9/GPL/openjdk-16.0.1_linux-x64_bin.tar.gz",
    "name": "openjdk-16.0.1_linux-x64_bin.tar.gz",
    "openjdk_version": "16.0.1+9"
  },
  {
    "feature_version": 15,
    "link": "https://download.java.net/java/GA/jdk15.0.2/0d1cfde4252546c6931946de8db48ee2/7/GPL/openjdk-15.0.2_linux-x64_bin.tar.gz",
    "name": "openjdk-15.0.2_linux-x64_bin.tar.gz",
    "openjdk_version": "15.0.2+7"
  },
  {
    "feature_version": 14,
    "link": "https://download.java.net/java/GA/jdk14.0.2/205943a0976c4ed48cb16f1043c5c647/12/GPL/openjdk-14.0.2_linux-x64_bin.tar.gz",
    "name": "openjdk-14.0.2_linux-x64_bin.tar.gz",
    "openjdk_version": "14.0.2+12"
  },
  {
    "feature_version": 13,
    "link": "https://download.java.net/java/GA/jdk13.0.2/d4173c853231432d94f001e99d882ca7/8/GPL/openjdk-13.0.2_linux-x64_bin.tar.gz",
    "name": "openjdk-13.0.2_linux-x64_bin.tar.gz",
    "openjdk_version": "13.0.2+8"
  },
  {
    "feature_version": 12,
    "link": "https://download.java.net/java/GA/jdk12.0.2/e482c34c86bd4bf8b56c0b35558996b9/10/GPL/openjdk-12.0.2_linux-x64_bin.tar.gz",
    "name": "openjdk-12.0.2_linux-x64_bin.tar.gz",
    "openjdk_version": "12.0.2+10"
  },
  {
    "feature_version": 11,
    "link": "https://download.java.net/java/GA/jdk11/9/GPL/openjdk-11.0.2_linux-x64_bin.tar.gz",
    "name": "openjdk-11.0.2_linux-x64_bin.tar.gz",
    "openjdk_version": "11.0.2+9"
  },
  {
    "feature_version": 10,
    "link": "https://download.java.net/java/GA/jdk10/10.0.2/19aef61b38124481863b1413dce1855f/13/openjdk-10.0.2_linux-x64_bin.tar.gz",
    "name": "openjdk-10.0.2_linux-x64_bin.tar.gz",
    "openjdk_version": "10.0.2+13"
  },
  {
    "feature_version": 9,
    "link": "https://download.java.net/java/GA/jdk9/9.0.4/binaries/openjdk-9.0.4_linux-x64_bin.tar.gz",
    "name": "openjdk-9.0.4_linux-x64_bin.tar.gz",
    "openjdk_version": "9.0.4+11"
  }
]
EOF
)
MOST_RECENT_FEATURE_RELEASE="$(jq -r '[.[] | select(has("pre") | not) | .feature_version ] | sort | reverse | .[0]' <<<"${LATEST_RELEASES}")"
MOST_RECENT_FEATURE_EA_RELEASE="$(jq -r '[.[] | select(has("pre")) | .feature_version ] | sort | reverse | .[0]' <<<"${LATEST_RELEASES}")"

MOST_RECENT_OPENJDK_VERSION="$(jq -r '.[] | select(has("pre") | not) | select(.feature_version == '"${MOST_RECENT_FEATURE_RELEASE}"') | .openjdk_version' <<<"${LATEST_RELEASES}")"
MOST_RECENT_OPENJDK_EA_VERSION="$(jq -r '.[] | select(has("pre")) | select(.feature_version == '"${MOST_RECENT_FEATURE_EA_RELEASE}"') | .openjdk_version' <<<"${LATEST_RELEASES}")"

mkdir -p "${TARGET}"
pushd "${TARGET}"

echo -n "" > "tools-jdk"
echo -n "" > "wiki"

cat <<EOF >> "tools-jdk"
  - name: "openjdk-latest"
    home: "/opt/tools/java/openjdk/latest"
  - name: "openjdk-ea-latest"
    home: "/opt/tools/java/openjdk/ea-latest"
EOF

cat <<EOF >> "wiki"
* openjdk-latest <code>/opt/tools/java/openjdk/latest</code> = '''${MOST_RECENT_OPENJDK_VERSION}'''
* openjdk-ea-latest ('''EA''') <code>/opt/tools/java/openjdk/ea-latest</code> = '''${MOST_RECENT_OPENJDK_EA_VERSION}'''
EOF

for release_json in $(jq -c '.[]' <<<"${LATEST_RELEASES}"); do
  feature_version="$(jq -r '.feature_version' <<<"${release_json}")"
  url="$(jq -r '.link' <<<"${release_json}")"
  name="$(jq -r '.name' <<<"${release_json}")"
  openjdk_version="$(jq -r '.openjdk_version' <<<"${release_json}")"
  echo "Installing OpenJDK-${feature_version}"
  
  if ! echo "$(curl -sSL "${url}.sha256") ${name}" | sha256sum --quiet --status -c -; then
    curl -sSL -o "${name}" "${url}"
  fi

  release_folder="jdk-${feature_version}"
  mkdir -p "${release_folder}/${openjdk_version}"
  tar zxf "${name}" -C "${release_folder}/${openjdk_version}" --strip-components=1
  rm -f "${release_folder}/latest" || :
  ln -s "${openjdk_version}" "${release_folder}/latest"

  #find "./${release_folder}" -mindepth 1 -maxdepth 1 -type d ! '(' -name 'latest' -o -name "${openjdk_version}" ')' -prune -print -exec rm -rf {} \+

  cat <<EOF >> "tools-jdk"
  - name: "openjdk-jdk${feature_version}-latest"
    home: "/opt/tools/java/openjdk/${release_folder}/latest"
EOF

  if [[ "$(jq -r '.pre' <<<"${release_json}")" == "ea" ]]; then
    ea="('''EA''') "
  else
    ea=""
  fi
  cat <<EOF >> "wiki"
* openjdk-jdk${feature_version}-latest ${ea}<code>/opt/tools/java/openjdk/${release_folder}/latest</code> = '''${openjdk_version}'''
EOF

done

rm -f "latest" || :
ln -s "jdk-${MOST_RECENT_FEATURE_RELEASE}/latest" "latest"

rm -f "ea-latest" || :
ln -s "jdk-${MOST_RECENT_FEATURE_EA_RELEASE}/latest" "ea-latest"

rm -f -- *.tar.gz
cat "wiki" "tools-jdk"
rm -f "wiki" "tools-jdk"

popd
