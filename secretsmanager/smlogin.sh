#!/bin/bash
# 
# Usage: source ./smlogin.sh
# This script must be sourced to export VAULT_TOKEN and VAULT_ADDR to your shell
#

# Vault Configuration
export VAULT_ADDR="https://secretsmanager.eclipse.org"
# export VAULT_USERNAME="sebastien.heurtematte@eclipse-foundation.org" # Optionally set your LDAP username here

# Check if vault CLI is available
if ! command -v vault &> /dev/null; then
    echo "❌ Error: vault CLI not found. Please install HashiCorp Vault CLI." >&2
    return 1 2>/dev/null || exit 1
fi

# Helper function to check if token is valid
_is_token_valid() {
    vault token lookup &>/dev/null
    return $?
}

# Helper function to load token from file
_load_token_from_file() {
    local token_file="$HOME/.vault-token"
    
    if [[ ! -f "$token_file" ]]; then
        echo "❌ Error: $token_file file not found." >&2
        return 1
    fi
    
    VAULT_TOKEN=$(cat "$token_file")
    export VAULT_TOKEN
    echo "✅ VAULT_TOKEN loaded from $token_file"
    
    if _is_token_valid; then
        echo "✅ VAULT_TOKEN is valid"
        return 0
    else
        echo "❌ Error: Loaded VAULT_TOKEN is invalid." >&2
        unset VAULT_TOKEN
        return 1
    fi
}

# Helper function to prompt for username
_get_vault_username() {
    if [[ -n "$VAULT_USERNAME" ]]; then
        echo "Using VAULT_USERNAME: $VAULT_USERNAME"
        return 0
    fi
    
    echo -n "Enter your LDAP username: "
    read -r VAULT_USERNAME
    
    if [[ -z "$VAULT_USERNAME" ]]; then
        echo "❌ Error: Username cannot be empty." >&2
        return 1
    fi
    
    return 0
}

# Helper function to perform LDAP login
_vault_ldap_login() {
    echo "🔐 Logging in to Vault using LDAP method..."
    
    if vault login -method=ldap -address="$VAULT_ADDR" username="$VAULT_USERNAME"; then
        echo "✅ Vault login successful"
        echo "Read token from ~/.vault-token..."
        if _load_token_from_file; then
            return 0
        fi
        return 0
    else
        echo "❌ Error: Vault LDAP login failed." >&2
        return 1
    fi
}

# Main function to manage Vault token authentication
vault_token() {
    # Check if VAULT_TOKEN is already set and valid
    if [[ -n "${VAULT_TOKEN:-}" ]] && _is_token_valid; then
        echo "✅ VAULT_TOKEN is already set and valid"
        return 0
    fi
    
    if [[ -n "${VAULT_TOKEN:-}" ]]; then
        echo "⚠️  VAULT_TOKEN is set but invalid or expired."
        unset VAULT_TOKEN
    fi

    # Try to load token from file
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        echo "Read token from ~/.vault-token..."
        if _load_token_from_file; then
            return 0
        fi
    fi
    
    # Get username and perform LDAP login
    _get_vault_username || return 1
    _vault_ldap_login || return 1

}
# Initialize Vault token
if ! vault_token; then
    return 1 2>/dev/null || exit 1
fi

# Export variables for the shell
export VAULT_TOKEN
export VAULT_ADDR

echo ""
echo "✅ Environment configured successfully!"
echo "   VAULT_ADDR: $VAULT_ADDR"
if [[ -n "${VAULT_TOKEN:-}" ]]; then
    echo "   VAULT_TOKEN: ${VAULT_TOKEN:0:10}..."
fi

