#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2020 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# This script creates a GPG key pair that can be used for deploying artifacts to Maven Central via Sonatype's OSSRH

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

IMAGE_TYPE="jdk"
ARCH="x64"
OS="linux"
HEAP_SIZE="normal"
mapfile -t AVAILABLE_RELEASES < <(curl -s https://api.adoptopenjdk.net/v3/info/available_releases | jq -r '.available_releases | sort | reverse | .[]')
MOST_RECENT_FEATURE_RELEASE="$(curl -s https://api.adoptopenjdk.net/v3/info/available_releases | jq -r '.most_recent_feature_release')"
MOST_RECENT_LTS="$(curl -s https://api.adoptopenjdk.net/v3/info/available_releases | jq -r '.most_recent_lts')"

MOST_RECENT_OPENJDK_VERSION="$(curl -sSL "https://api.adoptopenjdk.net/v3/info/release_versions?release_type=ga&sort_order=DESC&vendor=adoptopenjdk&version=%28${MOST_RECENT_FEATURE_RELEASE}%2C$((MOST_RECENT_FEATURE_RELEASE+1))%5D" | jq -r '[.versions[] | select(has("pre") | not)][0].openjdk_version')"
MOST_RECENT_LTS_OPENJDK_VERSION="$(curl -sSL "https://api.adoptopenjdk.net/v3/info/release_versions?release_type=ga&sort_order=DESC&vendor=adoptopenjdk&version=%28${MOST_RECENT_LTS}%2C$((MOST_RECENT_LTS+1))%5D" | jq -r '[.versions[] | select(has("pre") | not)][0].openjdk_version')"

JVM_IMPLS=(hotspot openj9)

mkdir -p "${TARGET}"
pushd "${TARGET}"

echo -n "" > "tools-jdk"
echo -n "" > "wiki"

for jvm_impl in "${JVM_IMPLS[@]}"; do
  cat <<EOF >> "tools-jdk"
  - name: "adoptopenjdk-${jvm_impl}-latest"
    home: "/opt/tools/java/adoptopenjdk/${jvm_impl}-latest"
  - name: "adoptopenjdk-${jvm_impl}-latest-lts"
    home: "/opt/tools/java/adoptopenjdk/${jvm_impl}-latest-lts"
EOF

  cat <<EOF >> "wiki"
===== With ${jvm_impl} =====
* adoptopenjdk-${jvm_impl}-latest <code>/opt/tools/java/adoptopenjdk/${jvm_impl}-latest</code> = '''${MOST_RECENT_OPENJDK_VERSION}'''
* adoptopenjdk-${jvm_impl}-latest-lts <code>/opt/tools/java/adoptopenjdk/${jvm_impl}-lts-latest</code> = '''${MOST_RECENT_LTS_OPENJDK_VERSION}'''
EOF

  for release in "${AVAILABLE_RELEASES[@]}"; do
    echo "Installing AdoptOpenJDK-${release}-${jvm_impl}"
    latest_release=$(curl -s "https://api.adoptopenjdk.net/v3/assets/latest/${release}/${jvm_impl}" | jq -r '.[] | select(.binary.architecture == "'"${ARCH}"'") | select(.binary.os == "'"${OS}"'") | select(.binary.heap_size == "'"${HEAP_SIZE}"'") | select(.binary.image_type == "'"${IMAGE_TYPE}"'")')
    checksum="$(jq -r '.binary.package.checksum' <<<"${latest_release}")"
    url="$(jq -r '.binary.package.link' <<<"${latest_release}")"
    name="$(jq -r '.binary.package.name' <<<"${latest_release}")"
    openjdk_version="$(jq -r '.version.openjdk_version' <<<"${latest_release}")"
    
    if ! echo "${checksum} ${name}" | sha256sum --quiet --status -c -; then
      curl -sSL -o "${name}" "${url}"
    fi
    
    release_folder="${jvm_impl}-${IMAGE_TYPE}-${release}"
    mkdir -p "${release_folder}/${openjdk_version}"
    tar zxf "${name}" -C "${release_folder}/${openjdk_version}" --strip-components=1
    rm -f "${release_folder}/latest" || :
    ln -s "${openjdk_version}" "${release_folder}/latest"

    #find "./${release_folder}" -mindepth 1 -maxdepth 1 -type d ! '(' -name 'latest' -o -name "${openjdk_version}" ')' -prune -print -exec rm -rf {} \+

cat <<EOF >> "tools-jdk"
  - name: "adoptopenjdk-${jvm_impl}-${IMAGE_TYPE}${release}-latest"
    home: "/opt/tools/java/adoptopenjdk/${release_folder}/latest"
EOF

cat <<EOF >> "wiki"
* adoptopenjdk-${jvm_impl}-${IMAGE_TYPE}${release}-latest <code>/opt/tools/java/adoptopenjdk/${release_folder}/latest</code> = '''${openjdk_version}'''
EOF

  done

  rm -f "${jvm_impl}-latest" || :
  ln -s "${jvm_impl}-${IMAGE_TYPE}-${MOST_RECENT_FEATURE_RELEASE}/latest" "${jvm_impl}-latest"

  rm -f "${jvm_impl}-latest-lts" || :
  ln -s "${jvm_impl}-${IMAGE_TYPE}-${MOST_RECENT_LTS}/latest" "${jvm_impl}-latest-lts"
done

rm -f -- *.tar.gz
cat "wiki" "tools-jdk"
rm -f "wiki" "tools-jdk"

popd