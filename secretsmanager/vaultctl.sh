#!/bin/bash
#
# vaultctl - HashiCorp Vault CLI Utility
# A command-line utility to manage Vault authentication and operations
#

# set -euo pipefail

# Configuration
export VAULT_ADDR="${VAULT_ADDR:-https://secretsmanager.eclipse.org}"

readonly VAULT_TOKEN_FILE="$HOME/.vault-token"
readonly CONFIG_FILE="$HOME/.vaultctl"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color


# Logging functions
log_info() {
    echo -e "${NC} $*"
}

log_success() {
    echo -e "${GREEN}✅ $*"
}

log_warning() {
    echo -e "${YELLOW}⚠️ $*" >&2
}

log_error() {
    echo -e "${RED}❌ $*" >&2
}

# Check if vault CLI is available
check_vault_cli() {
    if ! command -v vault &> /dev/null; then
        log_error "vault CLI not found. Please install HashiCorp Vault CLI."
        log_info "Visit: https://developer.hashicorp.com/vault/downloads"
        exit 1
    fi
}


# Load token from file
load_token_from_file() {
    # First, check if VAULT_TOKEN is already set in environment
    if [[ -n "${VAULT_TOKEN:-}" ]]; then
        log_info "VAULT_TOKEN already set in environment"
        export VAULT_TOKEN
        
        if _is_token_valid; then
            log_success "VAULT_TOKEN from environment is valid"
            return 0
        else
            log_warning "VAULT_TOKEN from environment is invalid, loading from file..."
            unset VAULT_TOKEN
        fi
    else
        log_info "VAULT_TOKEN not set in environment, loading from file..."
    fi

    # Load from file if not in environment or if invalid
    if [[ ! -f "$VAULT_TOKEN_FILE" ]]; then
        log_warning "$VAULT_TOKEN_FILE file not found." >&2
        return 1
    fi
    
    VAULT_TOKEN=$(cat "$VAULT_TOKEN_FILE")
    export VAULT_TOKEN
    log_info "VAULT_TOKEN loaded from $VAULT_TOKEN_FILE"    

    if _is_token_valid; then
        log_success "VAULT_TOKEN is valid"
        return 0
    else
        log_error "Loaded VAULT_TOKEN is invalid."
        unset VAULT_TOKEN
        return 1
    fi
}

_is_token_valid() {
    vault token lookup &>/dev/null    
    return $?
}

# Load username from config
load_username_from_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        if [[ -n "${VAULT_USERNAME:-}" ]]; then
            return 0
        fi
    fi
    return 1
}

# Save username to config
save_username_to_config() {
    local username="$1"
    echo "VAULT_USERNAME=\"$username\"" > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
}

# Prompt for username
get_vault_username() {
    local username=""
    
    # Try to load from config
    if load_username_from_config && [[ -n "${VAULT_USERNAME:-}" ]]; then
        log_info "Using saved username: $VAULT_USERNAME"
        return 0
    fi
    
    # Prompt for username
    echo -n "Enter your LDAP username: "
    read -r username
    
    if [[ -z "$username" ]]; then
        log_error "Username cannot be empty."
        return 1
    fi
    
    VAULT_USERNAME="$username"
    
    # Ask if user wants to save the username
    echo -n "Save username for future use? (y/n): "
    read -r save_choice
    if [[ "$save_choice" == "y" || "$save_choice" == "Y" ]]; then
        save_username_to_config "$username"
        log_success "Username saved to $CONFIG_FILE"
    fi
    
    return 0
}

# Perform LDAP login
vault_ldap_login() {
    log_info "Logging in to Vault using LDAP method..."
    log_info "Vault address: $VAULT_ADDR"
    
    if vault login -method=ldap -address="$VAULT_ADDR" username="$VAULT_USERNAME" >/dev/null; then
        log_success "Vault login successful"
        
        # Load the token that was just saved
        if load_token_from_file; then
            log_success "Token loaded and validated"
        fi
        return 0
    else
        log_error "Vault LDAP login failed."
        return 1
    fi
}

# Command: login
cmd_login() {
    # Check if token is already valid
    if load_token_from_file; then
        log_success "Already authenticated with a valid token"
        log_info "Token: ${VAULT_TOKEN:0:10}..."
        get_vault_username || return 1
        return 0
    fi
    
    log_info "No valid token found. Initiating login..."
    
    # Get username and perform login
    get_vault_username || return 1
    vault_ldap_login || return 1
    
    log_success "Authentication complete!"
    echo ""
    log_info "Your session is now authenticated with Vault"
    log_info "VAULT_ADDR: $VAULT_ADDR"
    log_info "Token stored in: $VAULT_TOKEN_FILE"
    log_info "VAULT_TOKEN: ${VAULT_TOKEN:0:10}..."
    echo ""
    log_info "To export variables to your shell, run:"
    echo "  eval \$(vaultctl export-vault)"

    export VAULT_TOKEN
    export VAULT_USERNAME
}

# Command: status
cmd_status() {    
    log_info "VAULT_ADDR: $VAULT_ADDR"
    
    # Load username if available
    load_username_from_config &>/dev/null || true
    if [[ -n "${VAULT_USERNAME:-}" ]]; then
        log_info "VAULT_USERNAME: $VAULT_USERNAME"
    fi
    
    if load_token_from_file; then
        log_success "Authenticated"
        log_info "VAULT_TOKEN: ${VAULT_TOKEN:0:10}..."
        echo ""
        vault token lookup 2>/dev/null | grep -E "(display_name|policies|creation_time|expire_time)"
    else
        log_warning "Not authenticated"
        log_info "Run 'vaultctl login' to authenticate"
    fi
}

# Command: logout
cmd_logout() {
    local token_to_revoke=""
    
    # Check if VAULT_TOKEN is set in environment
    if [[ -n "${VAULT_TOKEN:-}" ]]; then
        log_info "VAULT_TOKEN found in environment"
        token_to_revoke="$VAULT_TOKEN"
    elif [[ -f "$VAULT_TOKEN_FILE" ]]; then
        log_info "Loading token from file for revocation"
        token_to_revoke=$(cat "$VAULT_TOKEN_FILE" 2>/dev/null)
    fi
    
    # Revoke token if we have one
    if [[ -n "$token_to_revoke" ]]; then
        export VAULT_TOKEN="$token_to_revoke"
        if vault token revoke -self 2>/dev/null; then
            log_success "Token revoked successfully"
        else
            log_warning "Failed to revoke token (may already be expired)"
        fi
    fi
    
    # Remove token file if it exists
    if [[ -f "$VAULT_TOKEN_FILE" ]]; then
        rm -f "$VAULT_TOKEN_FILE"
        log_info "Token file removed"
    fi
    
    # Unset environment variable
    unset VAULT_TOKEN
    
    if [[ -n "$token_to_revoke" ]]; then
        log_success "Logged out successfully"
    else
        log_info "Not currently logged in"
    fi
}

# Function to retrieve secret from Vault
get_vault_secret() {
    local mount="$1"
    local path="$2"
    local key="$3"
    
    # Ensure token is loaded
    if ! load_token_from_file &>/dev/null; then
        log_error "Not authenticated. Run 'vaultctl login' first."
        return 1
    fi
    
    # Retrieve secret from Vault
    local value
    value=$(vault kv get -mount="$mount" -field="${key}" -address="$VAULT_ADDR" "$path" 2>&1)
    
    if [[ $? -eq 0 && -n "$value" ]]; then
        echo "$value"
        return 0
    else
        log_error "Failed to retrieve secret '$key' from $mount/$path"
        log_error "Vault error: $value"
        return 1
    fi
}

# Function to export secret as environment variable
export_secret_as_env() {
    local env_var="$1"
    local mount="$2"
    local path="$3"
    local key="$4"
    local prefix="${5:-}"
    local uppercase="${6:-false}"
    
    # Add prefix if provided
    if [[ -n "$prefix" ]]; then
        env_var="${prefix}${env_var}"
    fi
    
    # Convert to uppercase if requested
    if [[ "$uppercase" == "true" ]]; then
        env_var="${env_var^^}"
    fi
    
    log_info "Retrieving $env_var from Vault ($mount/$path)..." >&2
    
    local value
    value=$(get_vault_secret "$mount" "$path" "$key")
    
    if [[ $? -eq 0 ]]; then
        if [[ -z "$value" ]]; then
            log_warning "Retrieved empty value for $env_var from Vault."
            return 1
        else
            # Output export command for eval
            echo "export $env_var='$value'"
            log_success "$env_var loaded from Vault" >&2
            return 0
        fi
    else
        log_error "Failed to load $env_var from Vault."
        return 1
    fi
}

# Helper function to export all secrets from a path
_export_all_secrets() {
    local mount="$1"
    local path="$2"
    shift 2
    local prefix=""
    local uppercase="false"
    
    # Parse arguments - look for --prefix and --uppercase flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix)
                if [[ -n "${2:-}" ]]; then
                    prefix="$2"
                    shift 2
                else
                    log_error "--prefix requires an argument"
                    return 1
                fi
                ;;
            --uppercase)
                uppercase="true"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    # Ensure token is loaded
    if ! load_token_from_file &>/dev/null; then
        log_error "Not authenticated. Run 'vaultctl login' first."
        return 1
    fi
    
    log_info "Fetching all secrets from $mount/$path..." >&2
    
    # Get the secret data in JSON format
    local secret_data
    secret_data=$(vault kv get -mount="$mount" -format=json "$path" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to retrieve secrets from $mount/$path"
        log_error "Vault error: $secret_data"
        return 1
    fi
    
    # Extract all keys and values from the secret
    local keys
    keys=$(echo "$secret_data" | jq -r '.data.data | keys[]' 2>/dev/null)
    
    if [[ -z "$keys" ]]; then
        log_warning "No secrets found in $mount/$path"
        return 1
    fi
    
    log_info "Found secrets, exporting..." >&2
    
    # Export each key-value pair
    local success=true
    while IFS= read -r key; do
        local value
        value=$(echo "$secret_data" | jq -r ".data.data.\"$key\"" 2>/dev/null)
        
        if [[ $? -eq 0 && -n "$value" && "$value" != "null" ]]; then
            # Transform key to be a valid shell variable name
            # Replace invalid characters with underscores and prefix with VAR_ if starts with digit
            local var_name="$key"
            # Replace hyphens, dots, and other invalid chars with underscores
            var_name="${var_name//[-.]/_}"
                        # Add user-defined prefix if provided
            if [[ -n "$prefix" ]]; then
                var_name="${prefix}${var_name}"
            fi

            # If starts with a digit, prefix with VAR_
            if [[ "$var_name" =~ ^[0-9] ]]; then
                var_name="VAR_${var_name}"
            fi
            
            # Convert to uppercase if requested
            if [[ "$uppercase" == "true" ]]; then
                var_name="${var_name^^}"
            fi

            # Escape single quotes in value by replacing ' with '\''
            local escaped_value="${value//\'/\'\\\'\'}"
            echo "export $var_name='$escaped_value'"
            
            if [[ "$var_name" != "$key" ]]; then
                log_success "$key exported as $var_name" >&2
            else
                log_success "$key loaded from Vault as $var_name" >&2
            fi
        else
            log_warning "Failed to extract value for key: $key" >&2
            success=false
        fi
    done <<< "$keys"
    
    if [[ "$success" == "false" ]]; then
        return 1
    fi
    
    return 0
}

# Command: export-env
cmd_export_env() {
    local mount="${1:-}"
    local path="${2:-}"
    shift 2
    local prefix=""
    local uppercase="false"
    local mappings=()
    
    # Parse arguments - look for --prefix and --uppercase flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix)
                if [[ -n "${2:-}" ]]; then
                    prefix="$2"
                    shift 2
                else
                    log_error "--prefix requires an argument"
                    return 1
                fi
                ;;
            --uppercase)
                uppercase="true"
                shift
                ;;
            *)
                mappings+=("$1")
                shift
                ;;
        esac
    done
    
    if [[ -z "$mount" || -z "$path" || ${#mappings[@]} -eq 0 ]]; then
        log_error "Usage: vaultctl export-env <mount> <path> <ENV_VAR:key> [<ENV_VAR2:key2> ...] [--prefix PREFIX] [--uppercase]"
        echo ""
        echo "Examples:"
        echo "  # Export JENKINS_USERNAME from users/username secret"
        echo "  eval \$(vaultctl export-env users username JENKINS_USERNAME:JENKINS_USERNAME)"
        echo ""
        echo "  # Export multiple secrets"
        echo "  eval \$(vaultctl export-env users username JENKINS_USERNAME:JENKINS_USERNAME JENKINS_PASSWORD:JENKINS_PASSWORD)"
        echo ""
        echo "  # Use different env var name and vault key"
        echo "  eval \$(vaultctl export-env users myuser DB_PASS:password API_KEY:token)"
        echo ""
        echo "  # Add prefix to all exported variables"
        echo "  eval \$(vaultctl export-env users myuser USER:username PASS:password --prefix MY_)"
        echo ""
        echo "  # Convert variable names to uppercase"
        echo "  eval \$(vaultctl export-env users myuser user:username pass:password --uppercase)"
        echo ""
        echo "  # Combine prefix and uppercase"
        echo "  eval \$(vaultctl export-env users myuser user:username --prefix my_ --uppercase)"
        return 1
    fi
    
    # Process each mapping
    local success=true
    for mapping in "${mappings[@]}"; do
        if [[ "$mapping" =~ ^([^:]+):(.+)$ ]]; then
            local env_var="${BASH_REMATCH[1]}"
            local vault_key="${BASH_REMATCH[2]}"
            
            if ! export_secret_as_env "$env_var" "$mount" "$path" "$vault_key" "$prefix" "$uppercase"; then
                success=false
            fi
        else
            log_error "Invalid mapping format: $mapping (expected ENV_VAR:key)" >&2
            success=false
        fi
    done
    
    if [[ "$success" == "false" ]]; then
        return 1
    fi
    
    return 0
}

# Command: export-env-all
cmd_export_env_all() {
    local mount="${1:-}"
    local path="${2:-}"
    shift 2
    
    if [[ -z "$mount" || -z "$path" ]]; then
        log_error "Usage: vaultctl export-env-all <mount> <path> [--prefix PREFIX] [--uppercase]"
        echo ""
        echo "This command exports ALL secrets from the specified mount and path"
        echo "Optional prefix will be added to all exported variable names"
        echo ""
        echo "Examples:"
        echo "  # Export all secrets from users/username"
        echo "  eval \$(vaultctl export-env-all users <username>)"
        echo ""
        echo "  # Export all secrets from cbi mount with GH_ prefix"
        echo "  eval \$(vaultctl export-env-all cbi technology.cbi/github.com --prefix GH_)"
        echo ""
        echo "  # Export with uppercase variable names"
        echo "  eval \$(vaultctl export-env-all cbi technology.cbi/github.com --uppercase)"
        echo ""
        echo "  # Combine prefix and uppercase"
        echo "  eval \$(vaultctl export-env-all cbi technology.cbi/github.com --prefix gh_ --uppercase)"
        return 1
    fi
    
    # Export all secrets from the specified mount/path
    _export_all_secrets "$mount" "$path" "$@"
}

# Helper function to process user secrets with optional subpath
_process_user_secrets() {
    local subpath="${1:-}"
    shift
    local prefix=""
    local uppercase="false"
    local mappings=()
    
    # Parse arguments - look for --prefix and --uppercase flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix)
                if [[ -n "${2:-}" ]]; then
                    prefix="$2"
                    shift 2
                else
                    log_error "--prefix requires an argument"
                    return 1
                fi
                ;;
            --uppercase)
                uppercase="true"
                shift
                ;;
            *)
                mappings+=("$1")
                shift
                ;;
        esac
    done
    
    # Load username
    if ! load_username_from_config || [[ -z "${VAULT_USERNAME:-}" ]]; then
        log_error "No username configured. Run 'vaultctl login' first."
        return 1
    fi
    
    # Extract first part of email (before @)
    local user_path="${VAULT_USERNAME%%@*}"
    local full_path="$user_path"
    
    # Add subpath if provided
    if [[ -n "$subpath" ]]; then
        full_path="$user_path/$subpath"
    fi
    
    log_info "Using mount: users" >&2
    log_info "Using path: $full_path" >&2
    
    # Process each mapping
    local success=true
    for mapping in "${mappings[@]}"; do
        local env_var=""
        local vault_key=""
        
        # Check if mapping contains ':'
        if [[ "$mapping" =~ ^([^:]+):(.+)$ ]]; then
            # Explicit format: ENV_VAR:vault_key
            env_var="${BASH_REMATCH[1]}"
            vault_key="${BASH_REMATCH[2]}"
        elif [[ "$mapping" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            # Simple format: ENV_VAR (use same name for vault key)
            env_var="$mapping"
            vault_key="$mapping"
        else
            log_error "Invalid mapping format: $mapping (expected ENV_VAR or ENV_VAR:key)" >&2
            success=false
            continue
        fi
        
        if ! export_secret_as_env "$env_var" "users" "$full_path" "$vault_key" "$prefix" "$uppercase"; then
            success=false
        fi
    done
    
    if [[ "$success" == "false" ]]; then
        return 1
    fi
    
    return 0
}

# Command: export-users
cmd_export_users() {
    local mappings=("${@}")
    
    if [[ ${#mappings[@]} -eq 0 ]]; then
        log_error "Usage: vaultctl export-users <ENV_VAR[:key]> [<ENV_VAR2[:key2]> ...] [--prefix PREFIX] [--uppercase]"
        echo ""
        echo "This command automatically uses:"
        echo "  - Mount: users"
        echo "  - Path: first part of your email (before @)"
        echo ""
        echo "Examples:"
        echo "  # Simple format: ENV_VAR name = Vault key name"
        echo "  eval \$(vaultctl export-users JENKINS_USERNAME JENKINS_PASSWORD)"
        echo ""
        echo "  # Explicit format: ENV_VAR:vault_key"
        echo "  eval \$(vaultctl export-users JENKINS_USER:JENKINS_USERNAME JENKINS_PASS:JENKINS_PASSWORD)"
        echo ""
        echo "  # Add prefix to exported variables"
        echo "  eval \$(vaultctl export-users JENKINS_USERNAME JENKINS_PASSWORD --prefix CI_)"
        echo ""
        echo "  # Convert to uppercase"
        echo "  eval \$(vaultctl export-users jenkins_username --uppercase)"
        echo ""
        echo "  # Combine prefix and uppercase"
        echo "  eval \$(vaultctl export-users jenkins_username --prefix ci_ --uppercase)"
        echo ""
        echo "  # If your username is <username>@eclipse-foundation.org"
        echo "  # This will fetch from: users/<username>"
        return 1
    fi
    
    # Call helper function with no subpath
    _process_user_secrets "" "${mappings[@]}"
}

# Command: export-users-path
cmd_export_users_path() {
    local subpath="${1:-}"
    local mappings=("${@:2}")
    
    if [[ -z "$subpath" || ${#mappings[@]} -eq 0 ]]; then
        log_error "Usage: vaultctl export-users-path <subpath> <ENV_VAR[:key]> [<ENV_VAR2[:key2]> ...] [--prefix PREFIX] [--uppercase]"
        echo ""
        echo "This command allows you to access secrets in a subpath of your user directory."
        echo ""
        echo "Examples:"
        echo "  # Access secrets in users/username/cbi"
        echo "  eval \$(vaultctl export-users-path cbi JENKINS_USERNAME JENKINS_PASSWORD)"
        echo ""
        echo "  # Access secrets in users/username/github"
        echo "  eval \$(vaultctl export-users-path github GITHUB_TOKEN:token)"
        echo ""
        echo "  # Add prefix to exported variables"
        echo "  eval \$(vaultctl export-users-path github TOKEN:token --prefix GH_)"
        echo ""
        echo "  # Convert to uppercase"
        echo "  eval \$(vaultctl export-users-path github token --uppercase)"
        echo ""
        echo "  # If your username is <username>@eclipse-foundation.org"
        echo "  # This will fetch from: users/<username>/<subpath>"
        return 1
    fi
    
    # Call helper function with subpath
    _process_user_secrets "$subpath" "${mappings[@]}"
}

# Command: export-users-cbi
cmd_export_users_cbi() {
    local mappings=("${@}")
    
    if [[ ${#mappings[@]} -eq 0 ]]; then
        log_error "Usage: vaultctl export-users-cbi <ENV_VAR[:key]> [<ENV_VAR2[:key2]> ...] [--prefix PREFIX] [--uppercase]"
        echo ""
        echo "This command fetches secrets from users/<username>/cbi"
        echo ""
        echo "Examples:"
        echo "  # Simple format"
        echo "  eval \$(vaultctl export-users-cbi JENKINS_USERNAME JENKINS_PASSWORD)"
        echo ""
        echo "  # Explicit format"
        echo "  eval \$(vaultctl export-users-cbi JENKINS_USER:JENKINS_USERNAME)"
        echo ""
        echo "  # Add prefix to exported variables"
        echo "  eval \$(vaultctl export-users-cbi JENKINS_USERNAME JENKINS_PASSWORD --prefix CBI_)"
        echo ""
        echo "  # Convert to uppercase"
        echo "  eval \$(vaultctl export-users-cbi jenkins_username --uppercase)"
        return 1
    fi
    
    # Call helper function with 'cbi' subpath
    _process_user_secrets "cbi" "${mappings[@]}"
}

# Command: export-users-all
cmd_export_users_all() {
    # Load username
    if ! load_username_from_config || [[ -z "${VAULT_USERNAME:-}" ]]; then
        log_error "No username configured. Run 'vaultctl login' first."
        return 1
    fi
    
    # Extract first part of email (before @)
    local user_path="${VAULT_USERNAME%%@*}"
    
    log_info "Using mount: users" >&2
    log_info "Using path: $user_path" >&2
    
    # Export all secrets from user path
    _export_all_secrets "users" "$user_path" "$@"
}

# Command: export-users-path-all
cmd_export_users_path_all() {
    local subpath="${1:-}"
    shift
    
    if [[ -z "$subpath" ]]; then
        log_error "Usage: vaultctl export-users-path-all <subpath> [--prefix PREFIX] [--uppercase]"
        echo ""
        echo "This command exports ALL secrets from a subpath of your user directory."
        echo "Optional prefix will be added to all exported variable names"
        echo ""
        echo "Examples:"
        echo "  # Export all secrets from users/username/cbi"
        echo "  eval \$(vaultctl export-users-path-all cbi)"
        echo ""
        echo "  # Export all secrets from users/username/github with GH_ prefix"
        echo "  eval \$(vaultctl export-users-path-all github --prefix GH_)"
        echo ""
        echo "  # Export with uppercase variable names"
        echo "  eval \$(vaultctl export-users-path-all github --uppercase)"
        return 1
    fi
    
    # Load username
    if ! load_username_from_config || [[ -z "${VAULT_USERNAME:-}" ]]; then
        log_error "No username configured. Run 'vaultctl login' first."
        return 1
    fi
    
    # Extract first part of email (before @)
    local user_path="${VAULT_USERNAME%%@*}"
    local full_path="$user_path/$subpath"
    
    log_info "Using mount: users" >&2
    log_info "Using path: $full_path" >&2
    
    # Export all secrets from subpath
    _export_all_secrets "users" "$full_path" "$@"
}

# Command: export-users-cbi-all
cmd_export_users_cbi_all() {
    # Load username
    if ! load_username_from_config || [[ -z "${VAULT_USERNAME:-}" ]]; then
        log_error "No username configured. Run 'vaultctl login' first."
        return 1
    fi
    
    # Extract first part of email (before @)
    local user_path="${VAULT_USERNAME%%@*}"
    local full_path="$user_path/cbi"
    
    log_info "Using mount: users" >&2
    log_info "Using path: $full_path" >&2
    
    # Export all secrets from cbi subpath
    _export_all_secrets "users" "$full_path" "$@"
}

# Command: read
cmd_read() {
    local mount="${1:-}"
    local path="${2:-}"

    if [[ -z "$mount" || -z "$path" ]]; then
        log_error "Usage: vaultctl read <mount> <path>"
        echo ""
        echo "NOTE: path is the full path to the secret, including the field name"
        echo ""
        echo "Examples:"
        echo "  vaultctl read users <username>/cbi/JENKINS_USERNAME"
        echo "  vaultctl read cbi technology.cbi/github.com/api-token"
        return 1
    fi
    
    # Check if path is valid: don't start with a slash, at least one slash, does not end with a slash
    if [[ ! "$path" =~ ^[^/]+/.+[^/]$ ]]; then
        log_error "Path is invalid, slash issue. Path should not start or end with a slash and must contain at least one slash."
        return 1
    fi
    
    # Ensure token is loaded
    if ! load_token_from_file &>/dev/null; then
        log_error "Not authenticated. Run 'vaultctl login' first."
        return 1
    fi
    
    # Extract secret path and field
    local vault_secret_path="${path%/*}"
    local field="${path##*/}"
    
    local data
    data=$(vault kv get -mount="$mount" -field="$field" "$vault_secret_path" 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        log_error "Vault entry not found: vault kv get -mount=\"$mount\" -field=\"$field\" \"$vault_secret_path\""
        return 1
    fi
    
    echo -n "$data"
    return 0
}

# Command: write
cmd_write() {
    local mount="${1:-}"
    local path="${2:-}"
    shift 2
    local fields=("$@")
    
    if [[ -z "$mount" || -z "$path" || ${#fields[@]} -eq 0 ]]; then
        log_error "Usage: vaultctl write <mount> <path> [<key>=<secret> | <key>=@<secret_file> | @<secret_file>]"
        echo ""
        echo "NOTE: path is the full path to the secret without the field name"
        echo ""
        echo "Examples:"
        echo "  vaultctl write users myuser/cbi username=john password=secret123"
        echo "  vaultctl write users myuser/cbi token=@token.txt"
        echo "  vaultctl write users myuser/cbi @secrets.json"
        return 1
    fi
    
    # Ensure token is loaded
    if ! load_token_from_file &>/dev/null; then
        log_error "Not authenticated. Run 'vaultctl login' first."
        return 1
    fi
    
    # Test if file exists and is not empty
    test_file() {
        local secrets_file="$1"
        if [[ ! -f "$secrets_file" ]]; then
            log_error "File with secrets not found: $secrets_file"
            return 1
        fi
        if [[ ! -s "$secrets_file" ]]; then
            log_error "Secrets file is empty: $secrets_file"
            return 1
        fi
        return 0
    }
    
    # Validate fields
    OLDIFS=$IFS
    IFS=' '
    for field in ${fields}; do
        local key="${field%%=*}"
        local value=""
        
        if [[ "$field" == *"="* ]]; then
            value="${field#*=}"
        fi
        
        if [[ -z "$key" || -z "$value" ]] && [[ "$key" != @* && "$value" != @* ]]; then
            log_error "Field key '$key' or value '$value' is empty"
            return 1
        fi
        
        if [[ "$value" == @* ]]; then
            local secrets_file="${value#@}"
            if ! test_file "$secrets_file"; then
                return 1
            fi
        fi
        
        if [[ "$key" == @* ]]; then
            local secrets_file="${key#@}"
            if ! test_file "$secrets_file"; then
                return 1
            fi
        fi
    done
    IFS=$OLDIFS
    
    # Determine method (put or patch)
    local method="put"
    local secret_data
    secret_data=$(vault kv get -format="json" -mount="$mount" "$path" 2>/dev/null) || true
    
    if [[ -z "$secret_data" ]]; then
        log_info "Vault entry not found, creating new path: $path"
    else
        local secret_value
        secret_value=$(echo "$secret_data" | jq -r '.data.data' 2>/dev/null)
        if [[ "$secret_value" != "null" ]]; then
            method="patch"
        fi
    fi
    
    # Write to vault
    if vault kv "$method" -mount="$mount" "$path" "${fields[@]}" &>/dev/null; then
        log_success "Secret written to Vault: vault kv $method -mount=\"$mount\" \"$path\""
        return 0
    else
        log_error "Failed to write secret to Vault"
        return 1
    fi
}

# Command: export-vault
cmd_export_vault() {
    # Load token silently (redirect all output to /dev/null)
    if ! load_token_from_file &>/dev/null; then
        echo "echo 'Error: Not authenticated. Run \"vaultctl login\" first.' >&2" >&2
        return 1
    fi
    
    # Load username if available (silently)
    load_username_from_config &>/dev/null || true
    
    # Output ONLY export commands (no log messages)
    echo "export VAULT_ADDR='$VAULT_ADDR'"
    echo "export VAULT_TOKEN='$VAULT_TOKEN'"
    if [[ -n "${VAULT_USERNAME:-}" ]]; then
        echo "export VAULT_USERNAME='$VAULT_USERNAME'"
    fi
    return 0
}

# Show help
show_help() {
    cat << EOF
vaultctl - HashiCorp Vault CLI Utility

Usage: vaultctl <command> [options]

Commands:
  login
      Authenticate to Vault using LDAP
      
  logout
      Revoke token and remove credentials
      
  status
      Show current authentication status
      
  export-vault
      Export vault environment variables for current shell
      Usage: vaultctl export-vault
      
  read <mount> <path>
      Read a secret field from Vault
      Usage: vaultctl read <mount> <path>
      Note: path is the full path to the secret, including the field name
      
  write <mount> <path> <key>=<value> [...]
      Write secrets to Vault
      Usage: vaultctl write <mount> <path> [<key>=<secret> | <key>=@<secret_file> | @<secret_file>]
      Note: path is the full path to the secret without the field name
      
  export-env <mount> <path> <ENV_VAR:key> [<ENV_VAR2:key2> ...]
      Export secrets from Vault as environment variables
      Usage: vaultctl export-env <mount> <path> <ENV_VAR:key> [<ENV_VAR2:key2> ...]
      
  export-env-all <mount> <path>
      Export ALL secrets from specified mount and path
      Usage: vaultctl export-env-all <mount> <path>
      
  export-users <ENV_VAR[:key]> [<ENV_VAR2[:key2]> ...]
      Export specific secrets from users/<username>
      Usage: vaultctl export-users <ENV_VAR[:key]> [<ENV_VAR2[:key2]> ...]
      
  export-users-all
      Export ALL secrets from users/<username>
      Usage: vaultctl export-users-all
      
  export-users-path <subpath> <ENV_VAR[:key]> [<ENV_VAR2[:key2]> ...]
      Export specific secrets from users/<username>/<subpath>
      Usage: vaultctl export-users-path <subpath> <ENV_VAR[:key]> [<ENV_VAR2[:key2]> ...]
      
  export-users-path-all <subpath>
      Export ALL secrets from users/<username>/<subpath>
      Usage: vaultctl export-users-path-all <subpath>
      
  export-users-cbi <ENV_VAR[:key]> [<ENV_VAR2[:key2]> ...]
      Export specific secrets from users/<username>/cbi
      Usage: vaultctl export-users-cbi <ENV_VAR[:key]> [<ENV_VAR2[:key2]> ...]
      
  export-users-cbi-all
      Export ALL secrets from users/<username>/cbi
      Usage: vaultctl export-users-cbi-all
      
  help
      Show this help message

Environment Variables:
  VAULT_ADDR      Vault server address (default: https://secretsmanager.eclipse.org)
  VAULT_TOKEN     Authentication token (set after login)
  VAULT_USERNAME  LDAP username (optional)

Examples:
  vaultctl login                                        # Authenticate to Vault
  vaultctl status                                       # Check authentication status
  eval \$(vaultctl export-vault)                         # Export auth variables to current shell
  
  # Read secrets (output to stdout)
  vaultctl read users <username>/JENKINS_USERNAME
  vaultctl read cbi technology.cbi/github.com/api-token
  
  # Write secrets
  vaultctl write users myuser/cbi username=john password=******
  vaultctl write cbi technology.cbi/github.com api-token=***** password=******
  
  # Export secrets as environment variables
  eval \$(vaultctl export-users JENKINS_USERNAME JENKINS_PASSWORD) # Export specific user secrets
  eval \$(vaultctl export-users jenkins_username --prefix CI_ --uppercase) # With prefix and uppercase
  eval \$(vaultctl export-users-all)                     # Export ALL secrets from user path
  eval \$(vaultctl export-users-all --prefix PREFIX_ --uppercase) # ALL with prefix and uppercase
  eval \$(vaultctl export-users-path cbi JENKINS_USERNAME) # Export specific from users/<username>/cbi
  eval \$(vaultctl export-users-path cbi JENKINS_USERNAME --prefix CBI_) # With prefix
  eval \$(vaultctl export-users-cbi-all)                 # Export ALL secrets from cbi subpath
  eval \$(vaultctl export-env users myuser USER:username PASS:password) # Export secrets as env vars
  eval \$(vaultctl export-env users myuser user:username --prefix MY_ --uppercase) # With prefix and uppercase
  eval \$(vaultctl export-env-all users <username>) # Export ALL from specified mount/path
  eval \$(vaultctl export-env-all cbi technology.cbi/github.com --prefix GH_ --uppercase) # With options
  vaultctl logout                                       # Log out and revoke token

Configuration:
  Username saved in: $CONFIG_FILE
  Token stored in:   $VAULT_TOKEN_FILE

EOF
}

# Main function
main() {
    check_vault_cli
    
    local command="${1:-help}"
    
    case "$command" in
        login)
            cmd_login
            ;;
        logout)
            cmd_logout
            ;;
        status)
            cmd_status
            ;;
        export-vault)
            cmd_export_vault
            ;;
        read)
            shift
            cmd_read "$@"
            ;;
        write)
            shift
            cmd_write "$@"
            ;;
        export-env)
            shift
            cmd_export_env "$@"
            ;;
        export-env-all)
            shift
            cmd_export_env_all "$@"
            ;;
        export-users)
            shift
            cmd_export_users "$@"
            ;;
        export-users-all)
            shift
            cmd_export_users_all "$@"
            ;;
        export-users-path)
            shift
            cmd_export_users_path "$@"
            ;;
        export-users-path-all)
            shift
            cmd_export_users_path_all "$@"
            ;;
        export-users-cbi)
            shift
            cmd_export_users_cbi "$@"
            ;;
        export-users-cbi-all)
            shift
            cmd_export_users_cbi_all "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
