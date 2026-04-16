#!/bin/bash

# Source .env with error checking
if [ -f .env ]; then
    set -a  # Export all variables
    source .env
    set +a
else
    echo "Error: .env file not found. Please copy from example.env and configure."
    exit 1
fi

# Use configured key path or default
SSH_DIR="${SSH_DIR:-$HOME/.ssh}"
KEY_FILE="${KEY_FILE:-$SSH_DIR/id_rsa}"
ANSIBLE_USER="${ANSIBLE_USER:-$USER}"

# Generate an SSH key if it doesn't already exist
if [ ! -f "$KEY_FILE" ]; then
    echo "Generating SSH key at $KEY_FILE..."
    mkdir -p "$SSH_DIR"
    ssh-keygen -t rsa -b 4096 -N "" -f "$KEY_FILE" -C "homelab-$(hostname)"
else
    echo "SSH key already exists at $KEY_FILE. Skipping generation."
fi

# Function to copy SSH keys for a specific environment
copy_keys_for_env() {
    local env_name=$1
    local masters_var=$2
    local nodes_var=$3
    local enabled_var=$4
    
    # Check if this environment is enabled
    if [ "${enabled_var}" != "true" ]; then
        echo "Skipping ${env_name} (K3S_ENABLED_${env_name^^}=${enabled_var})"
        return 0
    fi
    
    echo ""
    echo "========================================="
    echo "Environment: ${env_name}"
    echo "========================================="
    
    # Validate that we have hosts for this environment
    if [ -z "$masters_var" ] && [ -z "$nodes_var" ]; then
        echo "Warning: No hosts configured for ${env_name}. Skipping."
        return 0
    fi
    
    # Build host list from env vars (comma-separated to space-separated)
    local HOSTS=""
    if [ -n "$masters_var" ]; then
        HOSTS="$HOSTS $(echo "$masters_var" | tr ',' ' ')"
    fi
    if [ -n "$nodes_var" ]; then
        HOSTS="$HOSTS $(echo "$nodes_var" | tr ',' ' ')"
    fi
    
    # Track failures for this environment
    local ENV_FAILED_HOSTS=""
    local SUCCESS_COUNT=0
    
    # Copy the SSH key to each host
    for host in $HOSTS; do
        host=$(echo "$host" | xargs)  # trim whitespace
        [ -z "$host" ] && continue
        
        echo ""
        echo "Copying SSH key to $ANSIBLE_USER@$host..."
        
        if ssh-copy-id -i "${KEY_FILE}.pub" "${ANSIBLE_USER}@${host}"; then
            echo "  ✓ Success"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            echo "  ✗ Failed"
            ENV_FAILED_HOSTS="$ENV_FAILED_HOSTS $host"
            ALL_FAILED_HOSTS="$ALL_FAILED_HOSTS ${env_name}:$host"
        fi
    done
    
    echo ""
    echo "Environment ${env_name} complete: ${SUCCESS_COUNT} succeeded"
    if [ -n "$ENV_FAILED_HOSTS" ]; then
        echo "Failed hosts:${ENV_FAILED_HOSTS}"
        return 1
    fi
    return 0
}

# Initialize global failure tracking
ALL_FAILED_HOSTS=""

# Determine run mode
SETUP_ALL_ENVIRONMENTS="${SETUP_ALL_ENVIRONMENTS:-false}"
ENVIRONMENT="${ENVIRONMENT:-dev}"

if [ "${SETUP_ALL_ENVIRONMENTS}" == "true" ]; then
    echo "Mode: Copy SSH keys to ALL ENVIRONMENTS (dev, uat, prod)"
    echo ""
    
    # Process all three environments
    copy_keys_for_env "dev" "${K3S_MASTERS_DEV}" "${K3S_NODES_DEV}" "${K3S_ENABLED_DEV}"
    copy_keys_for_env "uat" "${K3S_MASTERS_UAT}" "${K3S_NODES_UAT}" "${K3S_ENABLED_UAT}"
    copy_keys_for_env "prod" "${K3S_MASTERS_PROD}" "${K3S_NODES_PROD}" "${K3S_ENABLED_PROD}"
    
else
    # Single environment mode
    echo "Mode: Copy SSH keys to SINGLE ENVIRONMENT (${ENVIRONMENT})"
    echo ""
    
    # Map environment-specific variables
    case "${ENVIRONMENT}" in
        dev)
            K3S_ENABLED_SINGLE="${K3S_ENABLED_DEV}"
            K3S_MASTERS_SINGLE="${K3S_MASTERS_DEV}"
            K3S_NODES_SINGLE="${K3S_NODES_DEV}"
            ;;
        uat)
            K3S_ENABLED_SINGLE="${K3S_ENABLED_UAT}"
            K3S_MASTERS_SINGLE="${K3S_MASTERS_UAT}"
            K3S_NODES_SINGLE="${K3S_NODES_UAT}"
            ;;
        prod)
            K3S_ENABLED_SINGLE="${K3S_ENABLED_PROD}"
            K3S_MASTERS_SINGLE="${K3S_MASTERS_PROD}"
            K3S_NODES_SINGLE="${K3S_NODES_PROD}"
            ;;
        *)
            # Fallback to legacy variables for backward compatibility
            echo "Environment '${ENVIRONMENT}' not recognized, trying legacy variables..."
            K3S_ENABLED_SINGLE="${K3S_ENABLED:-true}"
            K3S_MASTERS_SINGLE="${K3S_MASTERS}"
            K3S_NODES_SINGLE="${K3S_NODES}"
            ;;
    esac
    
    # Process single environment
    copy_keys_for_env "${ENVIRONMENT}" "${K3S_MASTERS_SINGLE}" "${K3S_NODES_SINGLE}" "${K3S_ENABLED_SINGLE}"
fi

# Final summary
echo ""
echo "========================================="
echo "SSH Key Copy Summary"
echo "========================================="

if [ -z "$ALL_FAILED_HOSTS" ]; then
    echo "✓ All SSH keys copied successfully!"
    echo ""
    echo "Next steps:"
    echo "  - Test connectivity: ssh ${ANSIBLE_USER}@<host>"
    echo "  - Run setup: ./setup.sh"
else
    echo "✗ Some hosts failed:"
    for failure in $ALL_FAILED_HOSTS; do
        echo "  - $failure"
    done
    echo ""
    echo "Troubleshooting:"
    echo "  - Ensure hosts are reachable: ping <host>"
    echo "  - Check username: ANSIBLE_USER=${ANSIBLE_USER}"
    echo "  - Verify password auth is enabled on remote hosts"
    echo "  - Check SSH service is running: systemctl status sshd"
    exit 1
fi
echo "========================================="
