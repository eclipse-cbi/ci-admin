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

source "${SCRIPT_FOLDER}/secretsmanager_wrapper.sh"

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
VAULT_MOUNT="cbi"
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

# Test cases for sm_write and sm_read
test_sm_write_read() {
    local result
    
    # Cleanup before test
    cleanup_vault "$VAULT_MOUNT" "$VAULT_PATH"

    ######## Test writing a simple value #############################################
    sm_write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_1"="$VAULT_VALUE_1"
    result=$(sm_read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_1")
    assert_equals "$VAULT_VALUE_1" "$result" "sm_write and sm_read for simple value"
    
    ######## Test overwriting a simple value #############################################
    sm_write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_1"="$VAULT_VALUE_2"
    result=$(sm_read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_1")
    assert_equals "$VAULT_VALUE_2" "$result" "sm_write and sm_read for overwritting same field"

    ######## Test writing add a new fields #############################################
    sm_write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_2"="$VAULT_VALUE_2"
    result=$(sm_read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_2")
    assert_equals "$VAULT_VALUE_2" "$result" "sm_write and sm_read for simple value"

    ######## Test writing from stdin #############################################
    echo "$VAULT_VALUE_3" | sm_write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_3=-"
    result=$(sm_read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_3")
    assert_equals "$VAULT_VALUE_3" "$result" "sm_write and sm_read from stdin"

    ######## Test writing from stdin mixed with value #############################################
    echo "$VAULT_VALUE_2" | sm_write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_1=$VAULT_VALUE_3" "$VAULT_KEY_3=-"
    result1=$(sm_read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_1")
    result2=$(sm_read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_3")
    assert_equals "$VAULT_VALUE_3" "$result1" "sm_write and sm_read from stdin mixed with value"
    assert_equals "$VAULT_VALUE_2" "$result2" "sm_write and sm_read from stdin mixed with value"

    ######## Test writing patch both fields #############################################
    sm_write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_1=$VAULT_VALUE_1" "$VAULT_KEY_2=$VAULT_VALUE_1"
    result1=$(sm_read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_2")
    result2=$(sm_read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_2")
    assert_equals "$VAULT_VALUE_1" "$result1" "sm_write and sm_read patch first key"
    assert_equals "$VAULT_VALUE_1" "$result2" "sm_write and sm_read patch second key"

    ######## Test writing a key and a value from a file #############################################
    sm_write "$VAULT_MOUNT" "$VAULT_PATH" "@$VAULT_FILE_PATH"
    result=$(sm_read "$VAULT_MOUNT" "$VAULT_PATH/file_key_value_test")
    assert_equals "file_secret_value" "$result" "sm_write and sm_read for file key/value content"

    ######## Test writing only a value from a file 1 #############################################
    sm_write "$VAULT_MOUNT" "$VAULT_PATH" "import_file1=@$VAULT_FILE_PATH"
    result=$(sm_read "$VAULT_MOUNT" "$VAULT_PATH/import_file1")
    assert_equals "$(cat "$VAULT_FILE_PATH")" "$result" "sm_write and sm_read for file content"

    ######## Test writing only a value from a file 2 #############################################
    sm_write "$VAULT_MOUNT" "$VAULT_PATH" "import_file2=-" < "$VAULT_FILE_PATH"
    result=$(sm_read "$VAULT_MOUNT" "$VAULT_PATH/import_file2")
    assert_equals "$(cat "$VAULT_FILE_PATH")" "$result" "sm_write and sm_read for file content"

    ######## Test writing multiple files #############################################
    sm_write "$VAULT_MOUNT" "$VAULT_PATH" "import_multi_file1=@$VAULT_FILE_PATH1" "import_multi_file2=@$VAULT_FILE_PATH2"
    result1=$(sm_read "$VAULT_MOUNT" "$VAULT_PATH/import_multi_file1")
    result2=$(sm_read "$VAULT_MOUNT" "$VAULT_PATH/import_multi_file2")
    assert_equals "$(cat "$VAULT_FILE_PATH1")" "$result1" "sm_write and sm_read for file content1"
    assert_equals "$(cat "$VAULT_FILE_PATH2")" "$result2" "sm_write and sm_read for file content2"

    ######## Test conditionnal read #############################################
    if sm_read "$VAULT_MOUNT" "$VAULT_PATH/$VAULT_KEY_1" &> /dev/null ; then
        echo -e "INFO: sm_read conditionnal test existing path \u2705"
    else
        echo -e "ERROR: sm_read conditionnal test existing path \u274c"
    fi

    # Cleanup after test
    cleanup_vault "$VAULT_MOUNT" "$VAULT_PATH"
}

# # Test cases for error handling
test_sm_read_errors() {
    local result
    local message

    ######## Test missing mount #############################################
    result=$(sm_read "" "$VAULT_PATH" 2>&1 || true)
    message="Error: Mount is required for -mount=\"\" \"$VAULT_PATH\". Usage: Usage: sm_read <mount> <path>"
    assert_equals "${message}" "${result}" "sm_read with missing mount"

    ######## Test missing path #############################################
    result=$(sm_read "$VAULT_MOUNT" "" 2>&1 || true)
    message="Error: Path is required for -mount=\"$VAULT_MOUNT\" \"\". Usage: Usage: sm_read <mount> <path>"
    assert_equals "${message}" "${result}" "sm_read with missing path"

    ######## Test path must not start by slash #############################################
    result=$(sm_read "$VAULT_MOUNT" "/XXXXXX" 2>&1 || true)
    message="Error: Path is invalid, slash issue for -mount=\"$VAULT_MOUNT\" \"/XXXXXX\". Usage: Usage: sm_read <mount> <path>"
    assert_equals "${message}" "${result}" "sm_read path must not start by slash"

    ######## Test path must not end by slash #############################################
    result=$(sm_read "$VAULT_MOUNT" "XXXXXX/" 2>&1 || true)
    message="Error: Path is invalid, slash issue for -mount=\"$VAULT_MOUNT\" \"XXXXXX/\". Usage: Usage: sm_read <mount> <path>"
    assert_equals "${message}" "${result}" "sm_read path must not end by slash"

    ######## Test path must have one slash #############################################
    result=$(sm_read "$VAULT_MOUNT" "XXXXXX" 2>&1 || true)
    message="Error: Path is invalid, slash issue for -mount=\"$VAULT_MOUNT\" \"XXXXXX\". Usage: Usage: sm_read <mount> <path>"
    assert_equals "${message}" "${result}" "sm_read path must have one slash"

    ######## Test non exiting path #############################################
    result=$(sm_read "$VAULT_MOUNT" "XXX/XXX" 2>&1 || true)
    message="ERROR: vault entry not found: vault kv get -mount=\"$VAULT_MOUNT\" -field=\"XXX\" \"XXX\""
    assert_equals "${message}" "${result}" "sm_read with non existing path"

    ######## Test conditionnal read #############################################
    if ! sm_read "$VAULT_MOUNT" "XXX/XXX" &> /dev/null ; then
        echo -e "INFO: sm_read conditionnal test non existing path \u2705"
    else
        echo -e "ERROR: sm_read conditionnal test non existing path \u274c"
    fi
}

test_sm_write_errors() {
    local result
    local message

    ######## Test missing mount #############################################
    result=$(sm_write "" "$VAULT_PATH" "$VAULT_KEY_1=$VAULT_VALUE_1" 2>&1 || true)
    message="Error: Mount is required for -mount=\"\" \"$VAULT_PATH\" \"$VAULT_KEY_1=$VAULT_VALUE_1\". Usage: sm_write <mount> <path> [<key>=<secret> | <key>=@<secret file> | @<secret file>]"
    assert_equals "${message}" "${result}" "sm_write with missing mount"

    ######## Test missing path #############################################
    result=$(sm_write "$VAULT_MOUNT" "" "$VAULT_KEY_1=$VAULT_VALUE_1" 2>&1 || true)
    message="Error: Path is required for -mount=\"$VAULT_MOUNT\" \"\" \"$VAULT_KEY_1=$VAULT_VALUE_1\". Usage: sm_write <mount> <path> [<key>=<secret> | <key>=@<secret file> | @<secret file>]"
    assert_equals "${message}" "${result}" "sm_write with missing path"

    ######## Test missing fields #############################################
    result=$(sm_write "$VAULT_MOUNT" "$VAULT_PATH" 2>&1 || true)
    message="Error: fields are required for -mount=\"$VAULT_MOUNT\" \"$VAULT_PATH\" \"\". Usage: sm_write <mount> <path> [<key>=<secret> | <key>=@<secret file> | @<secret file>]"
    assert_equals "${message}" "${result}" "sm_write with missing fields"

    ######## Test missing value in fields #############################################"
    result=$(sm_write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_1=$VAULT_VALUE_1 $VAULT_KEY_2=" 2>&1 || true)
    message="Error: Field key '$VAULT_KEY_2' or value '' empty for -mount=\"$VAULT_MOUNT\" \"$VAULT_PATH\" \"$VAULT_KEY_1=$VAULT_VALUE_1 $VAULT_KEY_2=\""
    assert_equals "${message}" "${result}" "sm_write with missing value in fields"

    ######## Test missing value in fields with only key ref #############################################"
    result=$(sm_write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_1=$VAULT_VALUE_1 $VAULT_KEY_2" 2>&1 || true)
    message="Error: Field key '$VAULT_KEY_2' or value '' empty for -mount=\"$VAULT_MOUNT\" \"$VAULT_PATH\" \"$VAULT_KEY_1=$VAULT_VALUE_1 $VAULT_KEY_2\""
    assert_equals "${message}" "${result}" "sm_write with missing value in fields with only key ref"

    ######## Test missing file for write #############################################"
    result=$(sm_write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_1=@test.json" 2>&1 || true)
    message="Error: File with secrets not found: test.json"
    assert_equals "${message}" "${result}" "sm_write with missing file"

    ######## Test missing file without key for write #############################################"
    result=$(sm_write "$VAULT_MOUNT" "$VAULT_PATH" "@test.json" 2>&1 || true)
    message="Error: File with secrets not found: test.json"
    assert_equals "${message}" "${result}" "sm_write with missing file without key "
    
    ######## Test empty file for write #############################################"
    result=$(sm_write "$VAULT_MOUNT" "$VAULT_PATH" "$VAULT_KEY_1=@${VAULT_EMPTY_FILE_PATH}" 2>&1 || true)
    message="Error: Secrets file is empty: ${VAULT_EMPTY_FILE_PATH}"
    assert_equals "${message}" "${result}" "sm_write with empty file"

    ######## Test empty file without key for write #############################################"
    result=$(sm_write "$VAULT_MOUNT" "$VAULT_PATH" "@${VAULT_EMPTY_FILE_PATH}" 2>&1 || true)
    message="Error: Secrets file is empty: ${VAULT_EMPTY_FILE_PATH}"
    assert_equals "${message}" "${result}" "sm_write with empty file without key"
}

# Run tests
echo -e "Passing tests for sm_read and sm_write...\n"
test_sm_write_read
echo -e "\nFailure tests for sm_read...\n"
test_sm_read_errors
echo -e "\nFailure tests for sm_write....\n"
test_sm_write_errors

echo -e "\nAll tests passed! \u2705"