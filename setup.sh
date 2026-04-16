#!/bin/bash

# Function to process a single environment
process_environment() {
    local env_name=$1
    local masters_var=$2
    local nodes_var=$3
    local enabled_var=$4
    local context_var=$5
    
    echo ""
    echo "========================================="
    echo "Processing Environment: ${env_name}"
    echo "========================================="
    
    # Set environment-specific variables
    local ANSIBLE_INVENTORY_PATH="${ANSIBLE_INVENTORY_BASE_PATH:-inventory}/${env_name}"
    local INVENTORY_FILE="${ANSIBLE_INVENTORY_PATH}/${ANSIBLE_INVENTORY_FILE:-hosts.ini}"
    
    # Check and create directory
    if [ ! -d "${ANSIBLE_INVENTORY_PATH}" ]; then
        echo "Creating directory: ${ANSIBLE_INVENTORY_PATH}"
        mkdir -p "${ANSIBLE_INVENTORY_PATH}"
    fi
    
    # Check if inventory file exists
    if [ ! -f "${INVENTORY_FILE}" ]; then
        echo "Creating inventory file from example..."
        cp inventory/example/hosts.ini "${INVENTORY_FILE}"
    fi
    
    # Set K3S_CONTEXT
    export K3S_CONTEXT=${context_var}
    
    # Add localhost section
    if [ -n "${K3S_USERNAME}" ]; then
        local REQUIRED_LOCAL_SECTION="[local]\nlocalhost ansible_connection=local ansible_user=${K3S_USERNAME}"
        add_section_if_not_exists "[local]" "$REQUIRED_LOCAL_SECTION" "${INVENTORY_FILE}"
    fi
    
    # Process K3s hosts if enabled
    if [ "${enabled_var}" == "true" ]; then
        echo "K3s is enabled for ${env_name}"
        
        if [ -n "${masters_var}" ]; then
            add_hosts_to_inventory "${INVENTORY_FILE}" "master" "${masters_var}"
        fi
        
        if [ -n "${nodes_var}" ]; then
            add_hosts_to_inventory "${INVENTORY_FILE}" "node" "${nodes_var}"
        fi
        
        # Ensure k3s_cluster section exists
        local REQUIRED_CLUSTER_SECTION="[k3s_cluster:children]\nmaster\nnode"
        add_section_if_not_exists "[k3s_cluster:children]" "$REQUIRED_CLUSTER_SECTION" "${INVENTORY_FILE}"
        
        echo "Inventory updated for ${env_name}"
        
        # Run playbook for this environment if requested
        if [ "${RUN_PLAYBOOK}" == "true" ]; then
            run_playbook_for_env "${env_name}" "${INVENTORY_FILE}"
        fi
    else
        echo "K3s is disabled for ${env_name}, inventory created but no hosts added"
    fi
    
    echo "Environment ${env_name} processing complete."
}

# Function to add hosts to a specific inventory file
add_hosts_to_inventory() {
    local inventory_file=$1
    local section=$2
    local ips_list=$3
    local ips=(${ips_list//,/ })
    
    # Check if the section exists, if not, add it
    if ! grep -q "^\[${section}\]$" "${inventory_file}"; then
        echo "[${section}]" >> "${inventory_file}"
    fi
    
    # Add IPs to the section
    for ip in "${ips[@]}"; do
        if ! sed -n "/^\[${section}\]$/,/^\[.*\]$/p" "${inventory_file}" | grep -q "^${ip}$"; then
            echo "Adding ${ip} to [${section}] in $(basename ${inventory_file})"
            sed -i "/^\[${section}\]$/a ${ip}" "${inventory_file}"
        fi
    done
}

# Function to run playbook for a specific environment
run_playbook_for_env() {
    local env_name=$1
    local inventory_file=$2
    
    echo ""
    echo "Running Ansible Playbook for ${env_name}..."
    echo "Inventory: ${inventory_file}"
    
    # Production confirmation
    if [ "${env_name}" == "prod" ]; then
        echo "⚠️  WARNING: You are targeting PRODUCTION environment!"
        read -p "Are you sure you want to continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Skipping production deployment."
            return 1
        fi
    fi
    
    # Run playbook
    ansible-playbook -i "${inventory_file}" homelab.yml
    
    # Show cluster info
    sleep 5
    echo ""
    echo "Cluster status for ${env_name}:"
    kubectl get namespaces --context=${env_name} 2>/dev/null || echo "Context ${env_name} not yet available"
}

# Function to add hosts to the inventory file (legacy, kept for compatibility)
add_hosts() {
    local section=$1
    local ips=(${2//,/ })
    
    # Check if the section exists, if not, add it
    if ! grep -q "^\[${section}\]$" "${INVENTORY_FILE}"; then
        echo "[${section}]" >> "${INVENTORY_FILE}"
    fi

    # Add IPs to the section if they're not already present
    for ip in "${ips[@]}"; do
        # This searches from the current section header until the next section header or EOF
        # and checks if the IP is already present
        if ! sed -n "/^\[${section}\]$/,/^\[.*\]$/p" "${INVENTORY_FILE}" | grep -q "^${ip}$"; then
            echo "Adding ${ip} to [${section}]"
            # Insert IPs before the next section starts or at the end of the file
            sed -i "/^\[${section}\]$/a ${ip}" "${INVENTORY_FILE}"
        fi
    done
}

# Function to add a section if it doesn't exist
add_section_if_not_exists() {
    local section="$1"
    local content="$2"
    local file="$3"

    # Check if the file contains the unique identifier of the section you want to add/ensure exists
    if ! grep -qF "$section" "$file"; then
        # If the unique identifier isn't found, append the required lines to the file
        echo -e "\n$content" >> "$file"
        echo "Added section $section to $file."
    else
        echo "The section $section already exists in $file."
    fi
}

# Function to check and enable passwordless SSH
enable_ssh_access() {
  local host=$1

  echo "Checking SSH access for $ANSIBLE_USER on $host..."
  
  sshpass -p "$SSH_PASSWORD" ssh -o BatchMode=yes -o ConnectTimeout=5 "$ANSIBLE_USER@$host" 'exit' 2>/dev/null

  if [ $? -ne 0 ]; then
    echo "Passwordless SSH not enabled on $host. Enabling now..."

    # Copy the SSH key to the remote host
    sshpass -p "$SSH_PASSWORD" ssh-copy-id "$ANSIBLE_USER@$host"

    if [ $? -ne 0 ];then
        echo "Failed to enable passwordless SSH on $host."
        return 1
    else
        echo "Passwordless SSH enabled successfully on $host."
    fi
  else
    echo "Passwordless SSH already enabled on $host."
  fi
}

# Function to check and enable passwordless sudo
enable_sudo_access() {
  local host=$1

  echo "Checking passwordless sudo access for $ANSIBLE_USER on $host..."
  
  ssh "$ANSIBLE_USER@$host" "echo '$SUDO_PASSWORD' | sudo -S -n true" 2>/dev/null

  if [ $? -ne 0 ]; then
    echo "Passwordless sudo not enabled on $host. Enabling now..."
    
    local sudo_file="/etc/sudoers.d/010-$ANSIBLE_USER-nopassword"
    ssh "$ANSIBLE_USER@$host" "echo '$SUDO_PASSWORD' | sudo -S bash -c 'echo \"$ANSIBLE_USER ALL=(ALL) NOPASSWD: ALL\" > $sudo_file'"

    if [ $? -ne 0 ]; then
        echo "Failed to enable passwordless sudo on $host."
        return 1
    else
        echo "Passwordless sudo enabled successfully on $host."
    fi

  else
    echo "Passwordless sudo already enabled on $host."
  fi
}

# Source the .env file if it exists
if [ -f .env ]; then
    while IFS= read -r line; do
      # Trim leading and trailing whitespace
      line=$(echo "$line" | sed 's/^[ \t]*//;s/[ \t]*$//')
      # Skip empty lines and lines starting with #
      if [[ "$line" && "${line:0:1}" != "#" ]]; then
        # Remove inline comments and export
        export "$(echo "$line" | cut -d'#' -f1 | sed 's/^[ \t]*//;s/[ \t]*$//')"
      fi
    done < .env
    echo ".env file exists and sourced."
else
    echo ".env file does not exist. Creating from example..."
    # Create .env file from example
    cp example.env .env
    echo ".env file created from example."
    echo "Please edit the .env file and run the script again."
    exit 0  # Exit script if .env was just created from example
fi

# Check if already in the repository directory
if [ -d "$REPO_NAME/.git" ]; then
    echo "Already in the repository directory."
    cd $REPO_NAME
elif [ "$(basename "$(pwd)")" = "$REPO_NAME" ]; then
    echo "Already in the repository directory."
else
    echo "Not in the repository directory. Cloning..."
    # Clone your GitHub repository
    git clone https://github.com/$GITHUB_USERNAME/$REPO_NAME.git
    cd $REPO_NAME
fi

# Check if virtual environment exists
if [ -d "venv" ]; then
    echo "Virtual environment already exists."
else
    # Create a Python virtual environment
    python3 -m venv venv
fi

## activate your venv
echo "Activating virtual environment..."
source venv/bin/activate

## install requirements
echo "Installing requirements..."
pip install -r requirements.txt

# Install ansible collections
echo "Installing Ansible collections..."
ansible-galaxy collection install -r collections/requirements.yml 2>/dev/null || echo "Collections may already be installed"

echo ""
echo "========================================="
echo "Environment Setup Mode"
echo "========================================="

# Determine run mode
RUN_PLAYBOOK=${RUN_PLAYBOOK:-true}
SETUP_ALL_ENVIRONMENTS=${SETUP_ALL_ENVIRONMENTS:-false}

if [ "${SETUP_ALL_ENVIRONMENTS}" == "true" ]; then
    echo "Mode: SETUP ALL ENVIRONMENTS (dev, uat, prod)"
    echo ""
    
    # Process all three environments
    process_environment "dev" "${K3S_MASTERS_DEV}" "${K3S_NODES_DEV}" "${K3S_ENABLED_DEV}" "${K3S_CONTEXT_DEV}"
    process_environment "uat" "${K3S_MASTERS_UAT}" "${K3S_NODES_UAT}" "${K3S_ENABLED_UAT}" "${K3S_CONTEXT_UAT}"
    process_environment "prod" "${K3S_MASTERS_PROD}" "${K3S_NODES_PROD}" "${K3S_ENABLED_PROD}" "${K3S_CONTEXT_PROD}"
    
    echo ""
    echo "========================================="
    echo "All Environment Inventories Created!"
    echo "========================================="
    echo ""
    echo "Created inventories in:"
    echo "  - inventory/dev/hosts.ini"
    echo "  - inventory/uat/hosts.ini"
    echo "  - inventory/prod/hosts.ini"
    echo ""
    echo "To deploy an environment, run:"
    echo "  ENVIRONMENT=dev ./setup.sh"
    echo "  ENVIRONMENT=uat ./setup.sh"
    echo "  ENVIRONMENT=prod ./setup.sh"
    echo ""
    echo "Or edit .env to set SETUP_ALL_ENVIRONMENTS=false and ENVIRONMENT=<env>"
    
else
    # Single environment mode (original behavior)
    ENVIRONMENT=${ENVIRONMENT:-dev}
    echo "Mode: SINGLE ENVIRONMENT (${ENVIRONMENT})"
    echo ""
    
    # Map environment-specific variables to generic ones for single mode
    case "${ENVIRONMENT}" in
        dev)
            K3S_ENABLED=${K3S_ENABLED_DEV}
            K3S_MASTERS=${K3S_MASTERS_DEV}
            K3S_NODES=${K3S_NODES_DEV}
            K3S_CONTEXT=${K3S_CONTEXT_DEV}
            ;;
        uat)
            K3S_ENABLED=${K3S_ENABLED_UAT}
            K3S_MASTERS=${K3S_MASTERS_UAT}
            K3S_NODES=${K3S_NODES_UAT}
            K3S_CONTEXT=${K3S_CONTEXT_UAT}
            ;;
        prod)
            K3S_ENABLED=${K3S_ENABLED_PROD}
            K3S_MASTERS=${K3S_MASTERS_PROD}
            K3S_NODES=${K3S_NODES_PROD}
            K3S_CONTEXT=${K3S_CONTEXT_PROD}
            ;;
    esac
    
    # Process single environment
    process_environment "${ENVIRONMENT}" "${K3S_MASTERS}" "${K3S_NODES}" "${K3S_ENABLED}" "${K3S_CONTEXT}"
    
    # If K3s is enabled, prompt for passwords and setup SSH/sudo
    if [ "${K3S_ENABLED}" == "true" ]; then
        # Prompt the user for SSH and sudo passwords
        read -sp "Enter SSH password for ${K3S_USERNAME}: " SSH_PASSWORD
        echo
        read -sp "Enter sudo password for ${K3S_USERNAME}: " SUDO_PASSWORD
        echo
        
        # Get the inventory file path for this environment
        ANSIBLE_INVENTORY_PATH="${ANSIBLE_INVENTORY_BASE_PATH:-inventory}/${ENVIRONMENT}"
        INVENTORY_FILE="${ANSIBLE_INVENTORY_PATH}/${ANSIBLE_INVENTORY_FILE:-hosts.ini}"
        
        # Extract the hosts from the [master] and [node] sections
        hosts=$(sed -n '/^\[master\]/,/^\[/p;/^\[node\]/,/^\[/p' "${INVENTORY_FILE}" | grep -E '^\s*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | awk '{print $1}')
        
        # Iterate through the extracted hosts
        for host in $hosts; do
            enable_ssh_access "$host"
            enable_sudo_access "$host"
        done
        
        # Run playbook for this environment
        echo ""
        echo "========================================="
        echo "Running Ansible Playbook"
        echo "Environment: ${ENVIRONMENT}"
        echo "Inventory: ${INVENTORY_FILE}"
        echo "========================================="
        echo ""
        
        ansible-playbook -i "${INVENTORY_FILE}" homelab.yml
        
        sleep 10
        
        echo ""
        echo "Cluster status:"
        kubectl get namespaces 2>/dev/null || echo "kubectl not configured yet"
        kubectl get nodes 2>/dev/null || echo ""
    fi
fi

echo ""
echo "Setup complete!"
