#!/usr/bin/env bash

#*******************************************************************************
# Copyright (c) 2024 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'
SCRIPT_FOLDER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

VAULTCTL="${SCRIPT_FOLDER}/vaultctl.sh"

# Test helper function for assertions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_description="$3"
    if [ "$expected" != "$actual" ]; then
        echo -e "INFO: Test failed: $test_description \u274c"
        echo "INFO: Expected: $expected"
        echo "INFO: Actual:   $actual"
        exit 1
    else
        echo -e "INFO: $test_description \u2705"
    fi
}

# Function to cleanup vault paths after tests
cleanup_vault() {
    local mount="$1"
    local path="$2"
    # vault kv delete -mount="$mount" "$path" > /dev/null 2>&1 || true

    echo "INFO: Start cleanup for path: ${path}"
    metadata=$(vault kv metadata get -mount="${mount}" -format=json "${path}" &> /dev/null)  || true
    data=$(echo "${metadata}" | jq '.data')
    [[ "${data}" == "null" ]] && return

    versions=$(echo "${metadata}" | jq '.data.versions | keys_unsorted[] | tonumber' | tr '\n' ',' | sed 's/\(.*\),/\1 /')
    echo "INFO: Path to delete ${path}, versions: ${versions}"
    if [[ -z "${versions}" ]]; then
      echo -e "WARN: Versions for: ${path} is empty!"
    else
      vault kv destroy -mount="${mount}" -versions="$versions" "${path}" > /dev/null 2>&1 || true
      vault kv metadata delete -mount="${mount}" "${path}" > /dev/null 2>&1 || true
    fi
    echo -e "INFO: End cleanup for path: ${path}\n"
}

# Setup for tests
VAULT_MOUNT="test"
VAULT_PATH="test/path"
VAULT_KEY_1="key1"
VAULT_VALUE_1="secret_value1"
VAULT_KEY_2="key2"
VAULT_VALUE_2="secret_value2"
VAULT_KEY_3="key3"
VAULT_VALUE_3="secret_value3"
VAULT_FILE_PATH="$(mktemp)"
VAULT_FILE_PATH1="$(mktemp)"
VAULT_FILE_PATH2="$(mktemp)"
VAULT_EMPTY_FILE_PATH="$(mktemp)"
echo '{"file_key_value_test":"file_secret_value"}' > "$VAULT_FILE_PATH"
echo '{"file_key_value_test1":"file_secret_value1"}' > "$VAULT_FILE_PATH1"
echo '{"file_key_value_test2":"file_secret_value2"}' > "$VAULT_FILE_PATH2"

# Test cases for vaultctl write and vaultctl read
test_vaultctl_write_read() {
    local result
    
    # Cleanup before test
    cleanup_vault "$VAULT_MOUNT" "$VAULT_PATH"

    ######## Test writing a simple value #############################################
    "$VAULTCTL" write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_1"="$VAULT_VALUE_1"
    result=$("$VAULTCTL" read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_1")
    assert_equals "$VAULT_VALUE_1" "$result" "vaultctl write and read for simple value"
    
    ######## Test overwriting a simple value #############################################
    "$VAULTCTL" write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_1"="$VAULT_VALUE_2"
    result=$("$VAULTCTL" read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_1")
    assert_equals "$VAULT_VALUE_2" "$result" "vaultctl write and read for overwritting same field"

    ######## Test writing add a new fields #############################################
    "$VAULTCTL" write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_2"="$VAULT_VALUE_2"
    result=$("$VAULTCTL" read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_2")
    assert_equals "$VAULT_VALUE_2" "$result" "vaultctl write and read for simple value"

    ######## Test writing from stdin #############################################
    echo "$VAULT_VALUE_3" | "$VAULTCTL" write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_3=-"
    result=$("$VAULTCTL" read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_3")
    assert_equals "$VAULT_VALUE_3" "$result" "vaultctl write and read from stdin"

    ######## Test writing from stdin mixed with value #############################################
    echo "$VAULT_VALUE_2" | "$VAULTCTL" write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_1=$VAULT_VALUE_3" "$VAULT_KEY_3=-"
    result1=$("$VAULTCTL" read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_1")
    result2=$("$VAULTCTL" read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_3")
    assert_equals "$VAULT_VALUE_3" "$result1" "vaultctl write and read from stdin mixed with value"
    assert_equals "$VAULT_VALUE_2" "$result2" "vaultctl write and read from stdin mixed with value"

    ######## Test writing patch both fields #############################################
    "$VAULTCTL" write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_1=$VAULT_VALUE_1" "$VAULT_KEY_2=$VAULT_VALUE_1"
    result1=$("$VAULTCTL" read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_2")
    result2=$("$VAULTCTL" read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_2")
    assert_equals "$VAULT_VALUE_1" "$result1" "vaultctl write and read patch first key"
    assert_equals "$VAULT_VALUE_1" "$result2" "vaultctl write and read patch second key"

    ######## Test writing a key and a value from a file #############################################
    "$VAULTCTL" write "$VAULT_MOUNT" "$VAULT_PATH" "@$VAULT_FILE_PATH"
    result=$("$VAULTCTL" read "$VAULT_MOUNT" "$VAULT_PATH/file_key_value_test")
    assert_equals "file_secret_value" "$result" "vaultctl write and read for file key/value content"

    ######## Test writing only a value from a file 1 #############################################
    "$VAULTCTL" write "$VAULT_MOUNT" "$VAULT_PATH" "import_file1=@$VAULT_FILE_PATH"
    result=$("$VAULTCTL" read "$VAULT_MOUNT" "$VAULT_PATH/import_file1")
    assert_equals "$(cat "$VAULT_FILE_PATH")" "$result" "vaultctl write and read for file content"

    ######## Test writing only a value from a file 2 #############################################
    "$VAULTCTL" write "$VAULT_MOUNT" "$VAULT_PATH" "import_file2=-" < "$VAULT_FILE_PATH"
    result=$("$VAULTCTL" read "$VAULT_MOUNT" "$VAULT_PATH/import_file2")
    assert_equals "$(cat "$VAULT_FILE_PATH")" "$result" "vaultctl write and read for file content"

    ######## Test writing multiple files #############################################
    "$VAULTCTL" write "$VAULT_MOUNT" "$VAULT_PATH" "import_multi_file1=@$VAULT_FILE_PATH1" "import_multi_file2=@$VAULT_FILE_PATH2"
    result1=$("$VAULTCTL" read "$VAULT_MOUNT" "$VAULT_PATH/import_multi_file1")
    result2=$("$VAULTCTL" read "$VAULT_MOUNT" "$VAULT_PATH/import_multi_file2")
    assert_equals "$(cat "$VAULT_FILE_PATH1")" "$result1" "vaultctl write and read for file content1"
    assert_equals "$(cat "$VAULT_FILE_PATH2")" "$result2" "vaultctl write and read for file content2"

    ######## Test conditionnal read #############################################
    if "$VAULTCTL" read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_1" &> /dev/null ; then
        echo -e "INFO: vaultctl read conditionnal test existing path \u2705"
    else
        echo -e "ERROR: vaultctl read conditionnal test existing path \u274c"
    fi

    # Cleanup after test
    cleanup_vault "$VAULT_MOUNT" "$VAULT_PATH"
}

# Test cases for error handling
test_vaultctl_read_errors() {
    local result
    local message

    ######## Test missing mount #############################################
    result=$("$VAULTCTL" read "" "$VAULT_PATH" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
    message="❌ Usage: vaultctl read <mount> <path>

NOTE: path is the full path to the secret, including the field name

Examples:
  vaultctl read users <username>/cbi/JENKINS_USERNAME
  vaultctl read cbi technology.cbi/github.com/api-token"
    assert_equals "${message}" "${result}" "vaultctl read with missing mount"

    ######## Test missing path #############################################
    result=$("$VAULTCTL" read "$VAULT_MOUNT" "" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
    message="❌ Usage: vaultctl read <mount> <path>

NOTE: path is the full path to the secret, including the field name

Examples:
  vaultctl read users <username>/cbi/JENKINS_USERNAME
  vaultctl read cbi technology.cbi/github.com/api-token"
    assert_equals "${message}" "${result}" "vaultctl read with missing path"

    ######## Test path must not start by slash #############################################
    result=$("$VAULTCTL" read "$VAULT_MOUNT" "/XXXXXX" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
    assert_equals "❌ Path is invalid, slash issue. Path should not start or end with a slash and must contain at least one slash." "${result}" "vaultctl read path must not start by slash"

    ######## Test path must not end by slash #############################################
    result=$("$VAULTCTL" read "$VAULT_MOUNT" "XXXXXX/" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
    assert_equals "❌ Path is invalid, slash issue. Path should not start or end with a slash and must contain at least one slash." "${result}" "vaultctl read path must not end by slash"

    ######## Test path must have one slash #############################################
    result=$("$VAULTCTL" read "$VAULT_MOUNT" "XXXXXX" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
    assert_equals "❌ Path is invalid, slash issue. Path should not start or end with a slash and must contain at least one slash." "${result}" "vaultctl read path must have one slash"

    ######## Test non exiting path #############################################
    result=$("$VAULTCTL" read "$VAULT_MOUNT" "XXX/XXX" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
    message="❌ Vault entry not found: vault kv get -mount=\"$VAULT_MOUNT\" -field=\"XXX\" \"XXX\""
    assert_equals "${message}" "${result}" "vaultctl read with non existing path"

    ######## Test conditionnal read #############################################
    if ! "$VAULTCTL" read "$VAULT_MOUNT" "XXX/XXX" &> /dev/null ; then
        echo -e "INFO: vaultctl read conditionnal test non existing path \u2705"
    else
        echo -e "ERROR: vaultctl read conditionnal test non existing path \u274c"
    fi
}

test_vaultctl_write_errors() {
    local result
    local message

    ######## Test missing mount #############################################
    result=$("$VAULTCTL" write "" "$VAULT_PATH" "$VAULT_KEY_1=$VAULT_VALUE_1" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
    message="❌ Usage: vaultctl write <mount> <path> [<key>=<secret> | <key>=@<secret_file> | @<secret_file>]

NOTE: path is the full path to the secret without the field name

Examples:
  vaultctl write users myuser/cbi username=john password=secret123
  vaultctl write users myuser/cbi token=@token.txt
  vaultctl write users myuser/cbi @secrets.json"
    assert_equals "${message}" "${result}" "vaultctl write with missing mount"

    ######## Test missing path #############################################
    result=$("$VAULTCTL" write "$VAULT_MOUNT" "" "$VAULT_KEY_1=$VAULT_VALUE_1" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
    message="❌ Usage: vaultctl write <mount> <path> [<key>=<secret> | <key>=@<secret_file> | @<secret_file>]

NOTE: path is the full path to the secret without the field name

Examples:
  vaultctl write users myuser/cbi username=john password=secret123
  vaultctl write users myuser/cbi token=@token.txt
  vaultctl write users myuser/cbi @secrets.json"
    assert_equals "${message}" "${result}" "vaultctl write with missing path"

    ######## Test missing fields #############################################
    result=$("$VAULTCTL" write "$VAULT_MOUNT" "$VAULT_PATH" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
    message="❌ Usage: vaultctl write <mount> <path> [<key>=<secret> | <key>=@<secret_file> | @<secret_file>]

NOTE: path is the full path to the secret without the field name

Examples:
  vaultctl write users myuser/cbi username=john password=secret123
  vaultctl write users myuser/cbi token=@token.txt
  vaultctl write users myuser/cbi @secrets.json"
    assert_equals "${message}" "${result}" "vaultctl write with missing fields"

    ######## Test missing value in fields #############################################"
    result=$("$VAULTCTL" write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_1=$VAULT_VALUE_1 $VAULT_KEY_2=" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
    message="❌ Field key '$VAULT_KEY_2' or value '' is empty"
    assert_equals "${message}" "${result}" "vaultctl write with missing value in fields"

    ######## Test missing value in fields with only key ref #############################################"
    result=$("$VAULTCTL" write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_1=$VAULT_VALUE_1 $VAULT_KEY_2" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
    message="❌ Field key '$VAULT_KEY_2' or value '' is empty"
    assert_equals "${message}" "${result}" "vaultctl write with missing value in fields with only key ref"

    ######## Test missing file for write #############################################"
    result=$("$VAULTCTL" write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_1=@test.json" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
    message="❌ File with secrets not found: test.json"
    assert_equals "${message}" "${result}" "vaultctl write with missing file"

    ######## Test missing file without key for write #############################################"
    result=$("$VAULTCTL" write "$VAULT_MOUNT" "$VAULT_PATH" "@test.json" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
    message="❌ File with secrets not found: test.json"
    assert_equals "${message}" "${result}" "vaultctl write with missing file without key "
    
    ######## Test empty file for write #############################################"
    result=$("$VAULTCTL" write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_1=@${VAULT_EMPTY_FILE_PATH}" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
    message="❌ Secrets file is empty: ${VAULT_EMPTY_FILE_PATH}"
    assert_equals "${message}" "${result}" "vaultctl write with empty file"

    ######## Test empty file without key for write #############################################"
    result=$("$VAULTCTL" write "$VAULT_MOUNT" "$VAULT_PATH" "@${VAULT_EMPTY_FILE_PATH}" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
    message="❌ Secrets file is empty: ${VAULT_EMPTY_FILE_PATH}"
    assert_equals "${message}" "${result}" "vaultctl write with empty file without key"
}

# Run tests
echo -e "Passing tests for vaultctl read and vaultctl write...\n"
test_vaultctl_write_read
echo -e "\nFailure tests for vaultctl read...\n"
test_vaultctl_read_errors
echo -e "\nFailure tests for vaultctl write....\n"
test_vaultctl_write_errors

echo -e "\nAll tests passed! \u2705"