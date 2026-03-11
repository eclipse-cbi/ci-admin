#!/bin/bash
#
# vaultctl - HashiCorp Vault CLI Utility
# A command-line utility to manage Vault authentication and operations
#

# Configuration
export VAULT_ADDR="${VAULT_ADDR:-https://secretsmanager.eclipse.org}"

readonly VAULT_TOKEN_FILE="$HOME/.vault-token"
readonly CONFIG_FILE="$HOME/.vaultctl"
readonly VAULT_CACHE_DIR="${HOME}/.vaultctl_cache"
VAULT_CACHE_TTL="${VAULT_CACHE_TTL:-3600}" # Cache TTL in seconds (default: 1 hour)
VAULT_PARALLEL="${VAULT_PARALLEL:-5}"     # Number of parallel scan workers

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color


# Logging functions
log_info() {
    echo -e "${NC} $*"
    return 0
}

log_success() {
    echo -e "${GREEN}✅ $*"
    return 0
}

log_warning() {
    echo -e "${YELLOW}⚠️ $*" >&2
    return 0
}

log_error() {
    echo -e "${RED}❌ $*" >&2
    return 0
}

# Check if vault CLI is available
check_vault_cli() {
    if ! command -v vault &> /dev/null; then
        log_error "vault CLI not found. Please install HashiCorp Vault CLI."
        log_info "Visit: https://developer.hashicorp.com/vault/downloads"
        exit 1
    fi
    return 0
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
        # Safely parse VAULT_USERNAME from config without executing the file
        local line username
        line="$(grep -m1 '^VAULT_USERNAME=' "$CONFIG_FILE" 2>/dev/null || true)"
        if [[ -n "$line" ]]; then
            username="${line#VAULT_USERNAME=}"
            # Remove optional surrounding double quotes
            username="${username%\"}"
            username="${username#\"}"
            if [[ -n "$username" ]]; then
                VAULT_USERNAME="$username"
                return 0
            fi
        fi
    fi
    return 1
}

# Save username to config
save_username_to_config() {
    local username="$1"
    echo "VAULT_USERNAME=\"$username\"" > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    return 0
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
    return 0
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
        return 0
    else
        log_warning "Not authenticated"
        log_info "Run 'vaultctl login' to authenticate"
        return 1
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
    return 0
}

# Validate shell identifier (variable name)
validate_shell_identifier() {
    local identifier="$1"
    local context="${2:-variable name}"
    
    if [[ ! "$identifier" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        log_error "Invalid $context: '$identifier'. Must match [A-Za-z_][A-Za-z0-9_]*"
        return 1
    fi
    return 0
}

# Shell-escape a value for safe eval
shell_escape_value() {
    local value="$1"
    # Use printf %q for robust shell escaping
    printf "%q" "$value"
    return 0
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
    
    # Validate prefix if provided
    if [[ -n "$prefix" ]]; then
        if ! validate_shell_identifier "$prefix" "prefix"; then
            return 1
        fi
    fi
    
    # Validate env_var before applying transformations
    if ! validate_shell_identifier "$env_var" "environment variable"; then
        return 1
    fi
    
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
            # Output export command for eval with proper escaping
            local escaped_value
            escaped_value=$(shell_escape_value "$value")
            echo "export $env_var=$escaped_value"
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
                    # Validate prefix
                    if ! validate_shell_identifier "$prefix" "prefix"; then
                        return 1
                    fi
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

            # Validate final variable name
            if ! validate_shell_identifier "$var_name" "generated variable name"; then
                log_warning "Skipping invalid variable name generated from key: $key" >&2
                success=false
                continue
            fi

            # Use robust shell escaping
            local escaped_value
            escaped_value=$(shell_escape_value "$value")
            echo "export $var_name=$escaped_value"
            
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
                    # Validate prefix
                    if ! validate_shell_identifier "$prefix" "prefix"; then
                        return 1
                    fi
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

# Command: mv
cmd_mv() {
    local mount="${1:-}"
    local src_path="${2:-}"
    local dst_path="${3:-}"

    if [[ -z "$mount" || -z "$src_path" || -z "$dst_path" ]]; then
        log_error "Usage: vaultctl mv <mount> <src-path> <dst-path>"
        echo ""
        echo "Move (rename) a secret path: copies all fields to the new path then deletes the source."
        echo ""
        echo "NOTE: paths must not start or end with a slash."
        echo ""
        echo "Examples:"
        echo "  vaultctl mv cbi technology.cbi/repo3.eclipse.org technology.cbi/repo.eclipse.org"
        echo "  vaultctl mv users myuser/old-cbi myuser/cbi"
        return 1
    fi

    # Basic path validation (no leading/trailing slash)
    for p in "$src_path" "$dst_path"; do
        if [[ "$p" =~ ^/ || "$p" =~ /$ ]]; then
            log_error "Path must not start or end with a slash: '$p'"
            return 1
        fi
    done

    if [[ "$src_path" == "$dst_path" ]]; then
        log_error "Source and destination paths are identical."
        return 1
    fi

    # Ensure token is loaded
    if ! load_token_from_file &>/dev/null; then
        log_error "Not authenticated. Run 'vaultctl login' first."
        return 1
    fi

    # Read all fields from source as JSON
    log_info "Reading secrets from: $mount/$src_path" >&2
    local secret_json
    secret_json=$(vault kv get -mount="$mount" -format=json "$src_path" 2>&1)
    if [[ $? -ne 0 ]]; then
        log_error "Source path not found or not readable: $mount/$src_path"
        log_error "Vault error: $secret_json"
        return 1
    fi

    # Extract the kv data object
    local kv_data
    kv_data=$(echo "$secret_json" | jq -r '.data.data' 2>/dev/null)
    if [[ -z "$kv_data" || "$kv_data" == "null" ]]; then
        log_error "No data found at: $mount/$src_path"
        return 1
    fi

    local field_count
    field_count=$(echo "$kv_data" | jq 'keys | length')
    log_info "Found $field_count field(s) to move." >&2

    # Check if destination already exists
    local dst_check
    dst_check=$(vault kv get -mount="$mount" -format=json "$dst_path" 2>/dev/null)
    if [[ -n "$dst_check" ]]; then
        log_warning "Destination already exists: $mount/$dst_path"
        echo -n "Overwrite? (y/N): "
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            log_info "Move cancelled."
            return 1
        fi
    fi

    # Build a temporary JSON file with the kv data to pass to vault kv put
    local tmp_payload
    tmp_payload=$(mktemp)
    # Convert {"key":"val",...} to key=value pairs via process substitution
    local -a kv_args=()
    while IFS= read -r key; do
        local val
        val=$(echo "$kv_data" | jq -r --arg k "$key" '.[$k]')
        # Write value to a temp file to avoid shell escaping issues
        local vtmp
        vtmp=$(mktemp)
        printf '%s' "$val" > "$vtmp"
        kv_args+=("${key}=@${vtmp}")
    done < <(echo "$kv_data" | jq -r 'keys[]')

    # Write to destination
    log_info "Writing secrets to: $mount/$dst_path" >&2
    if ! vault kv put -mount="$mount" "$dst_path" "${kv_args[@]}" &>/dev/null; then
        log_error "Failed to write secrets to destination: $mount/$dst_path"
        # Cleanup value temp files
        for arg in "${kv_args[@]}"; do rm -f "${arg#*=@}"; done
        rm -f "$tmp_payload"
        return 1
    fi
    log_success "Secrets written to: $mount/$dst_path"

    # Cleanup value temp files
    for arg in "${kv_args[@]}"; do rm -f "${arg#*=@}"; done
    rm -f "$tmp_payload"

    # Delete source
    log_info "Deleting source path: $mount/$src_path" >&2
    if ! vault kv metadata delete -mount="$mount" "$src_path" &>/dev/null; then
        log_warning "Could not delete source metadata at: $mount/$src_path"
        log_warning "The data has been copied to destination but source was NOT deleted."
        return 1
    fi
    log_success "Source deleted: $mount/$src_path"

    # Update local cache: replace old path with new path (no full rescan needed)
    local cache_file
    cache_file=$(_cache_file "$mount")
    if [[ -f "$cache_file" ]]; then
        _cache_rename_path "$mount" "$src_path" "$dst_path"
        log_info "Cache updated: $mount/$src_path → $mount/$dst_path"
    fi

    log_success "Move complete: $mount/$src_path → $mount/$dst_path"
    return 0
}

# Command: rm
cmd_rm() {
    local mount=""
    local path=""
    local force=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force)
                force=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                return 1
                ;;
            *)
                if [[ -z "$mount" ]]; then
                    mount="$1"
                elif [[ -z "$path" ]]; then
                    path="$1"
                else
                    log_error "Too many arguments."
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$mount" || -z "$path" ]]; then
        log_error "Usage: vaultctl rm [-f] <mount> <path>"
        echo ""
        echo "Permanently delete a secret path and all its versions/metadata."
        echo ""
        echo "Options:"
        echo "  -f, --force   Skip confirmation prompt"
        echo ""
        echo "NOTE: path must not start or end with a slash."
        echo ""
        echo "Examples:"
        echo "  vaultctl rm cbi technology.cbi/old-repo.eclipse.org"
        echo "  vaultctl rm users myuser/deprecated-key"
        echo "  vaultctl rm -f cbi technology.cbi/old-key     # no confirmation"
        return 1
    fi

    # Basic path validation (no leading/trailing slash)
    if [[ "$path" =~ ^/ || "$path" =~ /$ ]]; then
        log_error "Path must not start or end with a slash: '$path'"
        return 1
    fi

    # Ensure token is loaded
    if ! load_token_from_file &>/dev/null; then
        log_error "Not authenticated. Run 'vaultctl login' first."
        return 1
    fi

    # Check secret exists and show info
    log_info "Fetching info from: $mount/$path" >&2
    local secret_json
    secret_json=$(vault kv get -mount="$mount" -format=json "$path" 2>&1)
    if [[ $? -ne 0 ]]; then
        log_error "Path not found or not readable: $mount/$path"
        log_error "Vault error: $secret_json"
        return 1
    fi

    local kv_data
    kv_data=$(echo "$secret_json" | jq -r '.data.data' 2>/dev/null)
    local field_count=0
    if [[ -n "$kv_data" && "$kv_data" != "null" ]]; then
        field_count=$(echo "$kv_data" | jq 'keys | length')
    fi
    local version
    version=$(echo "$secret_json" | jq -r '.data.metadata.version // "?"' 2>/dev/null)

    echo ""
    log_warning "About to PERMANENTLY delete:"
    echo "  Mount   : $mount"
    echo "  Path    : $path"
    echo "  Fields  : $field_count"
    echo "  Version : $version"
    echo "  Action  : all versions and metadata will be destroyed (irreversible)"
    echo ""

    if [[ "$force" != true ]]; then
        echo -n "Type the path to confirm deletion ('$path'): "
        read -r confirm
        if [[ "$confirm" != "$path" ]]; then
            log_info "Deletion cancelled."
            return 1
        fi
    fi

    # Permanently delete all versions and metadata
    log_info "Deleting: $mount/$path" >&2
    if ! vault kv metadata delete -mount="$mount" "$path" &>/dev/null; then
        log_error "Failed to delete path: $mount/$path"
        return 1
    fi
    log_success "Permanently deleted: $mount/$path"

    # Invalidate local cache for this mount so next find reflects the deletion
    local cache_file
    cache_file=$(_cache_file "$mount")
    if [[ -f "$cache_file" ]]; then
        rm -f "$cache_file"
        log_info "Cache invalidated for mount: $mount"
    fi

    return 0
}

# Command: export-vault
cmd_export_vault() {
    # Load token silently (redirect all output to /dev/null)
    if ! load_token_from_file &>/dev/null; then
        echo "Error: Not authenticated. Run \"vaultctl login\" first." >&2
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

# Helper function to list paths recursively in Vault
# ─── Cache management for vault find ────────────────────────────────────────

# Returns the cache file path for a given mount
_cache_file() {
    echo "${VAULT_CACHE_DIR}/${1}.json"
}

# Returns 0 if the cache for a mount exists and is within TTL
_cache_is_valid() {
    local mount="$1"
    local cache_file
    cache_file=$(_cache_file "$mount")
    [[ -f "$cache_file" ]] || return 1
    local epoch now diff
    # Use the epoch stored inside the JSON (independent of filesystem timestamps)
    epoch=$(jq -r '.created_at_epoch // empty' "$cache_file" 2>/dev/null) || return 1
    [[ -n "$epoch" ]] || return 1
    now=$(date +%s)
    diff=$(( now - epoch ))
    [[ $diff -lt $VAULT_CACHE_TTL ]]
}

# Returns a human-readable age string for the cache of a mount (e.g. "5 minutes ago")
_cache_age_str() {
    local mount="$1"
    local cache_file epoch now diff
    cache_file=$(_cache_file "$mount")
    epoch=$(jq -r '.created_at_epoch // empty' "$cache_file" 2>/dev/null)
    [[ -z "$epoch" ]] && { echo "unknown"; return; }
    now=$(date +%s)
    diff=$(( now - epoch ))
    if   [[ $diff -lt 60 ]];   then echo "${diff}s ago"
    elif [[ $diff -lt 3600 ]]; then echo "$(( diff / 60 ))min ago"
    elif [[ $diff -lt 86400 ]]; then echo "$(( diff / 3600 ))h ago"
    else echo "$(( diff / 86400 ))d ago"
    fi
}

# Streams all cached paths for a mount to stdout
_cache_load() {
    local mount="$1"
    jq -r '.paths[]' "$(_cache_file "$mount")" 2>/dev/null
}

# Saves a newline-delimited list of paths (from a temp file) to the cache
# Cache file format:
#   {
#     "mount":            "<mount>",
#     "created_at":       "YYYY-MM-DD HH:MM:SS",
#     "created_at_epoch": <unix_timestamp>,
#     "ttl":              <seconds>,
#     "count":            <number_of_paths>,
#     "paths":            [ ... ]
#   }
_cache_save() {
    local mount="$1"
    local tmpfile="$2"
    mkdir -p "$VAULT_CACHE_DIR"
    chmod 700 "$VAULT_CACHE_DIR"
    local cache_file now_epoch now_human
    cache_file=$(_cache_file "$mount")
    now_epoch=$(date +%s)
    now_human=$(date '+%Y-%m-%d %H:%M:%S')
    # Build JSON: read paths from tmpfile, wrap with metadata
    jq -Rn \
        --arg mount       "$mount" \
        --arg created_at  "$now_human" \
        --argjson epoch   "$now_epoch" \
        --argjson ttl     "$VAULT_CACHE_TTL" \
        '{ mount: $mount,
           created_at: $created_at,
           created_at_epoch: $epoch,
           ttl: $ttl,
           count: ([inputs] | length),
           paths: [inputs] }' \
        < "$tmpfile" > "$cache_file"
    # jq consumes stdin twice with [inputs]; re-run correctly with slurpfile workaround
    # Use a two-pass approach: count separately then build
    local count
    count=$(wc -l < "$tmpfile")
    jq -Rn \
        --arg mount       "$mount" \
        --arg created_at  "$now_human" \
        --argjson epoch   "$now_epoch" \
        --argjson ttl     "$VAULT_CACHE_TTL" \
        --argjson count   "$count" \
        '{ mount: $mount,
           created_at: $created_at,
           created_at_epoch: $epoch,
           ttl: $ttl,
           count: $count,
           paths: [inputs] }' \
        < "$tmpfile" > "$cache_file"
    chmod 600 "$cache_file"
}

# Updates the cache after a rename: replaces old_path with new_path (if cache exists)
_cache_rename_path() {
    local mount="$1"
    local old_path="$2"
    local new_path="$3"
    local cache_file
    cache_file=$(_cache_file "$mount")
    [[ -f "$cache_file" ]] || return 0
    local tmp_updated
    tmp_updated=$(mktemp)
    # Replace the old entry with the new one, preserve all other metadata
    jq --arg old "$old_path" --arg new "$new_path" '
        .paths |= map(if . == $old then $new else . end)
        | .count = (.paths | length)
    ' "$cache_file" > "$tmp_updated" && mv "$tmp_updated" "$cache_file"
}

# Clears the cache for a given mount
_cache_clear() {
    local mount="$1"
    local cache_file
    cache_file=$(_cache_file "$mount")
    if [[ -f "$cache_file" ]]; then
        rm -f "$cache_file"
        log_success "Cache cleared for mount: $mount"
    else
        log_info "No cache found for mount: $mount"
    fi
}

# Clears all cached indexes
_cache_clear_all() {
    if [[ -d "$VAULT_CACHE_DIR" ]]; then
        local count=0
        for f in "${VAULT_CACHE_DIR}"/*.json; do
            [[ -f "$f" ]] || continue
            rm -f "$f"
            count=$(( count + 1 ))
        done
        log_success "Cleared $count cache file(s) from $VAULT_CACHE_DIR"
    else
        log_info "No cache directory found: $VAULT_CACHE_DIR"
    fi
}

# Shows cache status: for a specific mount or all mounts
_cache_info() {
    local mount="${1:-}"
    if [[ -n "$mount" ]]; then
        local cache_file
        cache_file=$(_cache_file "$mount")
        if [[ -f "$cache_file" ]]; then
            local created_at count ttl age
            created_at=$(jq -r '.created_at // "unknown"' "$cache_file" 2>/dev/null)
            count=$(jq -r '.count // "?"' "$cache_file" 2>/dev/null)
            ttl=$(jq -r '.ttl // "?"' "$cache_file" 2>/dev/null)
            age=$(_cache_age_str "$mount")
            log_info "Cache for '$mount': $count paths"
            log_info "  Created : $created_at ($age)"
            log_info "  TTL     : ${ttl}s"
            if _cache_is_valid "$mount"; then
                log_success "Cache is valid"
            else
                log_warning "Cache is expired"
            fi
        else
            log_info "No cache found for mount: $mount"
        fi
    else
        if [[ -d "$VAULT_CACHE_DIR" ]]; then
            local found=false
            log_info "Cache directory: $VAULT_CACHE_DIR (TTL: ${VAULT_CACHE_TTL}s)"
            for f in "${VAULT_CACHE_DIR}"/*.json; do
                [[ -f "$f" ]] || continue
                found=true
                local name created_at count age valid_str
                name=$(basename "$f" .json)
                created_at=$(jq -r '.created_at // "unknown"' "$f" 2>/dev/null)
                count=$(jq -r '.count // "?"' "$f" 2>/dev/null)
                age=$(_cache_age_str "$name")
                if _cache_is_valid "$name"; then valid_str="valid"; else valid_str="expired"; fi
                log_info "  $name: $count paths, created: $created_at ($age) [$valid_str]"
            done
            [[ "$found" == "false" ]] && log_info "No cache files found in $VAULT_CACHE_DIR"
        else
            log_info "No cache directory: $VAULT_CACHE_DIR"
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

# Global state for find (cmd_find scope only)
_VAULT_FIND_COUNT=0

# ──── Queue-based parallel scan ──────────────────────────────────────────────
#
# Design: counter tracks "paths queued + paths in-flight" (never decremented on
# pop, only decremented when an item's processing is fully complete).
# This guarantees termination detection: counter=0 ⟺ all work is done.
#
#  _vault_try_pop    – atomic pop; outputs "stop", "wait", or "path:<p>"
#  _vault_finish_item – atomic: push N subdirs + counter += (N-1)
#  _vault_worker_body – worker main loop

# Atomic pop from work queue.
# Outputs to stdout:
#   stop      → counter=0, worker must exit
#   wait      → queue empty but in-flight work remains, worker must wait
#   path:<p>  → item claimed (p may be empty = mount root)
_vault_try_pop() {
    local work_dir="$1"
    (
        flock -x 9
        local counter
        counter=$(cat "${work_dir}/counter.txt" 2>/dev/null || echo 0)
        if [[ $counter -le 0 ]]; then
            echo "stop"
        else
            local f path
            for f in "${work_dir}/queue"/[0-9]*.item; do
                [[ -f "$f" ]] || break   # handles no-match (nullglob off)
                path=$(cat "$f" 2>/dev/null)
                rm -f "$f"
                echo "path:${path}"
                exit 0                   # exit subshell with found item
            done
            echo "wait"
        fi
    ) 9>"${work_dir}/queue.lock"
}

# Atomic: push child subdirs to queue and update counter by (N_subdirs - 1).
# This is the ONLY operation that modifies both queue and counter.
_vault_finish_item() {
    local work_dir="$1"; shift
    local subdirs=("$@")
    (
        flock -x 9
        local seq
        seq=$(cat "${work_dir}/queue/.seq" 2>/dev/null || echo 0)
        local subdir
        for subdir in "${subdirs[@]}"; do
            printf '%s' "$subdir" > "${work_dir}/queue/$(printf '%012d' $seq).item"
            seq=$(( seq + 1 ))
        done
        echo "$seq" > "${work_dir}/queue/.seq"
        local counter
        counter=$(cat "${work_dir}/counter.txt" 2>/dev/null || echo 0)
        echo $(( counter + ${#subdirs[@]} - 1 )) > "${work_dir}/counter.txt"
    ) 9>"${work_dir}/queue.lock"
}

# Worker: pops paths from the shared queue and scans them until counter=0.
_vault_worker_body() {
    local mount="$1"
    local worker_id="$2"
    local work_dir="$3"
    local wout="${work_dir}/worker_${worker_id}.txt"
    local wprog="${work_dir}/progress_${worker_id}.txt"
    touch "$wout" "$wprog"

    while true; do
        local pop_result
        pop_result=$(_vault_try_pop "$work_dir")
        case "$pop_result" in
            stop) break ;;
            wait)
                printf '' > "$wprog"   # clear progress: worker is idle
                sleep 0.05
                continue ;;
            path:*)
                local path="${pop_result#path:}"
                printf '%s/%s' "$mount" "$path" > "$wprog"

                local result subdirs=()
                result=$(vault kv list -mount="$mount" -format=json "$path" 2>/dev/null)

                if [[ $? -eq 0 && -n "$result" && "$result" != "null" ]]; then
                    while IFS= read -r item; do
                        [[ -z "$item" ]] && continue
                        local full="${path:+${path}/}${item}"
                        if [[ "$item" == */ ]]; then
                            subdirs+=("${full%/}")
                        else
                            echo "${full%/}" >> "$wout"
                        fi
                    done < <(echo "$result" | jq -r '.[]' 2>/dev/null)
                fi

                # Atomically push children + adjust counter
                _vault_finish_item "$work_dir" "${subdirs[@]}"
                ;;
        esac
    done
    printf '' > "$wprog"  # clear on clean exit
}

# Background progress monitor: reads worker progress files and updates a single
# terminal line. Runs until the done-signal file is created.
_vault_progress_monitor() {
    local work_dir="$1"
    local done_signal="$2"
    local term_width prefix max_path_len display active total_paths last_path

    while [[ ! -f "$done_signal" ]]; do
        active=0
        total_paths=0
        last_path=""

        # Read each worker's current progress file
        for pf in "${work_dir}"/progress_*.txt; do
            [[ -f "$pf" ]] || continue
            local p
            p=$(cat "$pf" 2>/dev/null)
            if [[ -n "$p" ]]; then
                active=$(( active + 1 ))
                last_path="$p"
            fi
        done

        # Count total paths found so far across all worker files
        for wf in "${work_dir}"/worker_*.txt; do
            [[ -f "$wf" ]] || continue
            local c
            c=$(wc -l < "$wf" 2>/dev/null || echo 0)
            total_paths=$(( total_paths + c ))
        done

        term_width=$(tput cols 2>/dev/null || echo 80)
        prefix=" Scanning [${active} workers • ${total_paths} paths]: "
        max_path_len=$(( term_width - ${#prefix} - 1 ))
        display="${last_path:-...}"
        if [[ ${#display} -gt $max_path_len && $max_path_len -gt 3 ]]; then
            display="...${display: -$(( max_path_len - 3 ))}"
        fi
        printf "\r\033[K%s%s" "$prefix" "$display" >&2
        sleep 0.1
    done
}

# Command: find
cmd_find() {
    local mount="${1:-}"
    shift || true
    local pattern="*"
    local use_cache=true
    local write_cache=true
    local bare=false
    local clear_mode=false
    local clear_all=false
    local show_cache_info=false

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-cache)
                use_cache=false
                shift ;;
            --no-cache-write)
                write_cache=false
                shift ;;
            -b|--bare)
                bare=true
                shift ;;
            --clear-cache)
                clear_mode=true
                shift ;;
            --clear-all-cache)
                clear_all=true
                shift ;;
            --cache-info)
                show_cache_info=true
                shift ;;
            --cache-ttl)
                if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then
                    VAULT_CACHE_TTL="$2"
                    shift 2
                else
                    log_error "--cache-ttl requires a numeric value in seconds"
                    return 1
                fi ;;
            --parallel)
                if [[ -n "${2:-}" && "$2" =~ ^[1-9][0-9]*$ ]]; then
                    VAULT_PARALLEL="$2"
                    shift 2
                else
                    log_error "--parallel requires a positive integer"
                    return 1
                fi ;;
            -*)
                log_error "Unknown option: $1"
                return 1 ;;
            *)
                pattern="$1"
                shift ;;
        esac
    done

    # --clear-all-cache doesn't need a mount
    if [[ "$clear_all" == "true" ]]; then
        _cache_clear_all
        return $?
    fi

    if [[ -z "$mount" ]]; then
        log_error "Usage: vaultctl find <mount> [pattern] [options]"
        echo ""
        echo "Search for secret paths in a Vault mount matching a glob pattern."
        echo ""
        echo "Arguments:"
        echo "  mount     - The Vault mount point to search (e.g., users, cbi)"
        echo "  pattern   - Optional glob pattern to match paths (default: * = all)"
        echo ""
        echo "Options:"
        echo "  --no-cache          Bypass cache and scan live (still updates cache)"
        echo "  --no-cache-write    Scan live without updating the cache"
        echo "  -b, --bare          Output raw paths only (no progress, no log messages)"
        echo "  --clear-cache       Clear cached index for this mount and exit"
        echo "  --clear-all-cache   Clear all mount caches and exit (mount not required)"
        echo "  --cache-info        Show cache status for this mount (or all if no mount)"
        echo "  --cache-ttl <s>     Override cache TTL in seconds (default: ${VAULT_CACHE_TTL}s)"
        echo "  --parallel <n>      Number of parallel scan workers (default: ${VAULT_PARALLEL})"
        echo ""
        echo "Examples:"
        echo "  vaultctl find users                     # List all paths in users mount"
        echo "  vaultctl find users '*/cbi/*'           # Paths under any user's cbi dir"
        echo "  vaultctl find cbi 'technology.cbi/*'   # Paths under technology.cbi"
        echo "  vaultctl find users 'myuser/*'          # Paths for a specific user"
        echo "  vaultctl find users --clear-cache       # Clear cached index for users"
        echo "  vaultctl find --clear-all-cache         # Clear all caches"
        echo "  vaultctl find users --cache-info        # Show cache status for users"
        echo "  vaultctl find --cache-info              # Show status of all caches"
        return 1
    fi

    # --clear-cache: remove cache for this mount and exit
    if [[ "$clear_mode" == "true" ]]; then
        _cache_clear "$mount"
        return $?
    fi

    # --cache-info: display cache metadata and exit
    if [[ "$show_cache_info" == "true" ]]; then
        _cache_info "$mount"
        return $?
    fi

    # Ensure token is loaded
    if ! load_token_from_file &>/dev/null; then
        log_error "Not authenticated. Run 'vaultctl login' first."
        return 1
    fi

    [[ "$bare" == "false" ]] && log_info "Searching in mount '$mount' with pattern: $pattern" >&2

    _VAULT_FIND_COUNT=0

    if [[ "$use_cache" == "true" ]] && _cache_is_valid "$mount"; then
        # ── Cache hit: filter client-side and stream results immediately ──────
        local cache_file created_at age count_indexed
        cache_file=$(_cache_file "$mount")
        created_at=$(jq -r '.created_at // "unknown"' "$cache_file" 2>/dev/null)
        count_indexed=$(jq -r '.count // "?"' "$cache_file" 2>/dev/null)
        age=$(_cache_age_str "$mount")
        if [[ "$bare" == "false" ]]; then
            log_info "Using cached index — $count_indexed paths, cached on $created_at ($age)" >&2
            echo "" >&2
        fi

        while IFS= read -r cached_path; do
            if [[ "$cached_path" == $pattern ]]; then
                echo "$cached_path"
                _VAULT_FIND_COUNT=$(( _VAULT_FIND_COUNT + 1 ))
            fi
        done < <(_cache_load "$mount")
    else
        # ── Cache miss: live scan with progressive display ────────────────────
        if [[ "$bare" == "false" ]]; then
            if [[ "$use_cache" == "true" ]]; then
                log_info "No valid cache found, scanning live..." >&2
            else
                log_info "Cache bypassed, scanning live..." >&2
            fi
        fi

        # ── Queue-based parallel scan ─────────────────────────────────────────
        # Exactly VAULT_PARALLEL workers share a global work queue.
        # Counter = paths queued + paths in-flight; reaches 0 when all is done.
        local work_dir
        work_dir=$(mktemp -d)
        local queue_dir="${work_dir}/queue"
        local all_paths_file="${work_dir}/all_paths.txt"
        local done_signal="${work_dir}/.done"
        mkdir -p "$queue_dir"
        touch "$all_paths_file"

        # Seed: mount root (empty path), counter=1
        printf '' > "${queue_dir}/000000000000.item"
        echo "1" > "${work_dir}/counter.txt"
        echo "1" > "${queue_dir}/.seq"

        # Start background progress monitor (skipped in bare mode)
        local monitor_pid=""
        if [[ "$bare" == "false" ]]; then
            _vault_progress_monitor "$work_dir" "$done_signal" &
            monitor_pid=$!
        fi

        # Launch exactly VAULT_PARALLEL workers; they self-terminate via the queue
        local -a worker_pids=()
        local _wi
        for (( _wi=0; _wi<VAULT_PARALLEL; _wi++ )); do
            ( _vault_worker_body "$mount" "$_wi" "$work_dir" ) &
            worker_pids+=($!)
        done

        # Wait for all workers to finish
        wait "${worker_pids[@]}" 2>/dev/null

        # Stop progress monitor
        touch "$done_signal"
        if [[ -n "$monitor_pid" ]]; then
            wait "$monitor_pid" 2>/dev/null || true
            printf "\r\033[K" >&2
        fi

        # Merge all worker outputs
        local f
        for f in "${work_dir}"/worker_*.txt; do
            [[ -f "$f" ]] && cat "$f" >> "$all_paths_file"
        done

        # Save full index to cache
        if [[ "$write_cache" == "true" && -s "$all_paths_file" ]]; then
            _cache_save "$mount" "$all_paths_file"
            if [[ "$bare" == "false" ]]; then
                local cache_count cached_at
                cache_count=$(wc -l < "$all_paths_file")
                cached_at=$(date '+%Y-%m-%d %H:%M:%S')
                log_info "Index of $cache_count paths saved to cache on $cached_at (TTL: ${VAULT_CACHE_TTL}s)\n" >&2
            fi
        fi

        # Filter and display results
        if [[ -s "$all_paths_file" ]]; then
            while IFS= read -r p; do
                if [[ "$p" == $pattern ]]; then
                    echo "$p"
                    _VAULT_FIND_COUNT=$(( _VAULT_FIND_COUNT + 1 ))
                fi
            done < "$all_paths_file"
        fi

        rm -rf "$work_dir"
    fi

    if [[ $_VAULT_FIND_COUNT -eq 0 ]]; then
        [[ "$bare" == "false" ]] && { echo "" >&2; log_warning "No paths found matching pattern: $pattern" >&2; }
        return 1
    fi

    if [[ "$bare" == "false" ]]; then
        echo "" >&2
        log_success "Found $_VAULT_FIND_COUNT path(s)" >&2
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
      
  find <mount> [pattern] [options]
      Search for secret paths in a Vault mount matching a glob pattern.
      A local index is cached to speed up subsequent searches on the same mount.
      Arguments:
        mount   - The Vault mount point to search (e.g., users, cbi)
        pattern - Optional glob pattern (default: * = all paths)
      Options:
        --no-cache          Bypass cache, scan live (still updates cache)
        --no-cache-write    Scan live without updating the cache
        -b, --bare          Output raw paths only (no progress, no log messages)
        --clear-cache       Clear cached index for this mount and exit
        --clear-all-cache   Clear all mount caches (mount not required)
        --cache-info        Show cache status for this mount (or all)
        --cache-ttl <s>     Override cache TTL in seconds (default: 3600)
        --parallel <n>      Number of parallel scan workers (default: ${VAULT_PARALLEL})
      
  mv <mount> <src-path> <dst-path>
      Move (rename) a secret path within a mount.
      Copies all fields to the new path then permanently deletes the source.
      Usage: vaultctl mv <mount> <src-path> <dst-path>
      
  rm <mount> <path> [-f]
      Permanently delete a secret path and all its versions/metadata.
      Usage: vaultctl rm [-f] <mount> <path>
      Options:
        -f, --force   Skip confirmation prompt
      
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
  
  # Move (rename) a secret path
  vaultctl mv cbi technology.cbi/repo3.eclipse.org technology.cbi/repo.eclipse.org
  vaultctl mv users myuser/old-path myuser/new-path

  # Bulk rename: find all paths matching a pattern and rename them with sed
  vaultctl find cbi '*repo3.*' -b | while read p; do vaultctl mv cbi "\$p" "\$(echo "\$p" | sed 's/repo3\.eclipse\.org/repo.eclipse.org/')"; done
  
  # Delete a secret path permanently
  vaultctl rm cbi technology.cbi/old-repo.eclipse.org
  vaultctl rm -f users myuser/deprecated-key              # skip confirmation
  
  # Find secret paths (with local cache)
  vaultctl find users                                   # List all paths in users mount (cached)
  vaultctl find users '*/cbi/*'                         # Find paths under any user's cbi dir
  vaultctl find cbi 'technology.cbi/*'                  # Find paths under technology.cbi
  vaultctl find users 'myuser/*' --no-cache             # Force live scan, update cache
  vaultctl find users --clear-cache                     # Invalidate cached index for users
  vaultctl find --clear-all-cache                       # Invalidate all cached indexes
  vaultctl find users --cache-info                      # Show cache status for users mount
  
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
    return 0
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
        mv)
            shift
            cmd_mv "$@"
            ;;
        rm|delete)
            shift
            cmd_rm "$@"
            ;;
        find)
            shift
            cmd_find "$@"
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
    return 0
}

main "$@"
