#!/usr/bin/env bash

#*******************************************************************************
# Copyright (c) 2025 Eclipse Foundation and others.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
#*******************************************************************************

# This file contains portions of code written with assistance from the Claude Sonnet AI model.

# Check secretsmanager structure level 1 in secrets engine 'cbi' and match with Eclipse projects API
# Reports divergences between API and secretsmanager secrets structure

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

IFS=$'\n\t'
SCRIPT_FOLDER="$(dirname "$(readlink -f "${0}")")"

CACHE_FILE="${SCRIPT_FOLDER}/projects.eclipse.org-api-cache.json"
VAULT_SECRETS_ENGINE="cbi"

# Exclude list - projects that should not be validated against the API
EXCLUDE_PATTERNS=(
  "foundation-internal."
  "oss."
  "research."
)

# Check if vault CLI is available
if ! command -v vault > /dev/null; then
  >&2 echo "ERROR: this program requires 'vault' CLI"
  exit 1
fi

# Authenticate with secretsmanager
SMLOGIN_SCRIPT="${SCRIPT_FOLDER}/../secretsmanager/smlogin.sh"

if [[ -z "${VAULT_TOKEN:-}" ]] || ! vault token lookup &>/dev/null 2>&1; then
  echo "Authenticating with Vault..."
  
  if [[ ! -f "${SMLOGIN_SCRIPT}" ]]; then
    >&2 echo "ERROR: smlogin.sh script not found at: ${SMLOGIN_SCRIPT}"
    >&2 echo "Please authenticate manually with: vault login"
    exit 1
  fi
  
  # Source the script to export VAULT_TOKEN
  # shellcheck disable=SC1090
  source "${SMLOGIN_SCRIPT}"
  SOURCE_EXIT_CODE=$?
  
  if [[ ${SOURCE_EXIT_CODE} -ne 0 ]]; then
    >&2 echo "ERROR: Authentication failed (exit code: ${SOURCE_EXIT_CODE})"
    exit 1
  fi
fi

# Final check: ensure VAULT_TOKEN is set and valid
if [[ -z "${VAULT_TOKEN:-}" ]]; then
  >&2 echo "ERROR: VAULT_TOKEN is not set after authentication"
  exit 1
fi

if ! vault token lookup &>/dev/null; then
  >&2 echo "ERROR: VAULT_TOKEN is invalid or expired"
  exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fetch projects from Eclipse API
_fetch_projects_api() {
  echo "Fetching projects from Eclipse API..."
  bash "${SCRIPT_FOLDER}/fetch_projects_api.sh"
  return 0
}

# Get all project IDs from API
_get_api_projects() {
  if [[ ! -f "${CACHE_FILE}" ]]; then
    _fetch_projects_api
  fi
  jq -r '.[].project_id' "${CACHE_FILE}" | sort
  return 0
}

# Get all level 1 secrets from Vault (secrets/cbi/*)
_get_vault_secrets() {
  echo "Fetching Vault secrets from '${VAULT_SECRETS_ENGINE}' engine..." >&2
  
  # List all level 1 paths in the cbi secrets engine
  # Using KV v2 secrets engine: vault kv list secrets/cbi
  vault kv list -format=json "${VAULT_SECRETS_ENGINE}/" 2>/dev/null | \
    jq -r '.[]' | \
    sed 's:/$::' | \
    sort
  return 0
}

# Main comparison function
_compare_vault_with_api() {
  local -a api_projects=()
  local -a vault_secrets=()
  local -a found_in_api=()
  local -a not_found_in_api=()
  local -a excluded=()
    
  # First, get secretsmanager secrets
  echo "========= Fetching secretsmanager secrets..."
  mapfile -t vault_secrets < <(_get_vault_secrets)
  echo "Secretsmanager secrets found: ${#vault_secrets[@]}"
  echo ""
  
  # Then, get API projects
  echo "========= Fetching Eclipse projects from API..."
  mapfile -t api_projects < <(_get_api_projects)
  echo "API Projects found: ${#api_projects[@]}"
  
  echo "Building API lookup table..."
  local -A api_lookup=()
  for project in "${api_projects[@]}"; do
    api_lookup["${project}"]=1
  done
  echo ""
  
  _should_exclude() {
    local secret="$1"
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
      if [[ "${secret}" == ${pattern}* ]]; then
        return 0
      fi
    done
    return 1
  }
  
  # Step 3: For each secretsmanager secret, check if it exists in API (or is excluded)
  echo "========= Comparing secretsmanager secrets with API projects..."
  echo ""
  
  if [[ ${#vault_secrets[@]} -gt 0 ]]; then
    for secret in "${vault_secrets[@]}"; do
      if _should_exclude "${secret}"; then
        excluded+=("${secret}")
      elif [[ -n "${api_lookup[${secret}]:-}" ]]; then
        found_in_api+=("${secret}")
      else
        not_found_in_api+=("${secret}")
      fi
    done
  fi
  
  # Display results
  echo -e "${GREEN}✓ Secretsmanager secrets found in API (${#found_in_api[@]}):${NC}"
  if [[ ${#found_in_api[@]} -gt 0 ]]; then
    printf '  - %s\n' "${found_in_api[@]}" | head -n 10
    if [[ ${#found_in_api[@]} -gt 10 ]]; then
      echo "  ... and $((${#found_in_api[@]} - 10)) more"
    fi
  else
    echo "  None"
  fi
  echo ""
  
  echo -e "${YELLOW}⊘ Secretsmanager secrets EXCLUDED from validation (${#excluded[@]}):${NC}"
  if [[ ${#excluded[@]} -gt 0 ]]; then
    printf '  - %s\n' "${excluded[@]}" | head -n 20
    if [[ ${#excluded[@]} -gt 20 ]]; then
      echo "  ... and $((${#excluded[@]} - 20)) more"
    fi
  else
    echo "  None"
  fi
  echo ""
  
  echo -e "${RED}✗ Secretsmanager secrets NOT found in API (${#not_found_in_api[@]}):${NC}"
  if [[ ${#not_found_in_api[@]} -gt 0 ]]; then
    printf '  - %s\n' "${not_found_in_api[@]}"
  else
    echo "  None"
  fi
  echo ""
  
  echo "==================================="
  echo "Summary:"
  echo "  Total Secretsmanager secrets: ${#vault_secrets[@]}"
  echo "  Found in API: ${#found_in_api[@]}"
  echo "  Excluded: ${#excluded[@]}"
  echo "  NOT found in API: ${#not_found_in_api[@]}"
  echo "==================================="
  
  if [[ ${#not_found_in_api[@]} -gt 0 ]]; then
    return 1
  fi
  return 0
}

_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Check secretsmanager structure level 1 in secrets engine 'cbi' and match with Eclipse projects API.
The script first lists all secrets in secretsmanager, then checks if each secret's project_id exists in the API.

Example: A Vault secret 'cbi/technology.cbi' should have a corresponding project_id 'technology.cbi' in the API.

PREREQUISITES:
  - HashiCorp Vault CLI installed (https://www.vaultproject.io/downloads)
  - VAULT_ADDR environment variable set (e.g., export VAULT_ADDR='https://vault.example.com:8200')
  - VAULT_TOKEN environment variable set or vault login completed

OPTIONS:
  -h, --help              Show this help message
  -r, --refresh           Force refresh of API cache
  
EXAMPLES:
  $(basename "$0")                    # Run validation and show report
  $(basename "$0") --refresh          # Force API cache refresh

EOF
  return 0
}

main() {
  local refresh=false
  
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        _usage
        exit 0
        ;;
      -r|--refresh)
        refresh=true
        shift
        ;;
      *)
        echo "Unknown option: $1"
        _usage
        exit 1
        ;;
    esac
  done
  
  if [[ "${refresh}" == true ]] && [[ -f "${CACHE_FILE}" ]]; then
    echo "Removing cache file..."
    rm -f "${CACHE_FILE}"
  fi

  _compare_vault_with_api
  return $?
}

main "$@"
