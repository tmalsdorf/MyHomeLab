#!/bin/bash

# Function to add hosts to the inventory file
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

# echo "Initializing localhost..."
# if [ "${K3S_ENABLED}" == "true" ]; then
#   ansible-galaxy collection install kubernetes.core
# fi

# Check and create ANSIBLE_INVENTORY_PATH directory if it doesn't exist
echo "Checking and creating ANSIBLE_INVENTORY_PATH directory..."
if [ ! -d "${ANSIBLE_INVENTORY_PATH}" ]; then
    mkdir -p "${ANSIBLE_INVENTORY_PATH}"
fi
# Check and create ANSIBLE_INVENTORY_FILE if it doesn't exist
echo "Checking and creating ANSIBLE_INVENTORY_FILE..."
INVENTORY_FILE="${ANSIBLE_INVENTORY_PATH}/${ANSIBLE_INVENTORY_FILE}"
if [ ! -f "${INVENTORY_FILE}" ]; then
    touch "${INVENTORY_FILE}"
fi
# Define localhost
# Define local section 
REQUIRED_LOCAL_SECTION="[local]\nlocalhost ansible_connection=local ansible_user=${K3S_USERNAME}"
# Ensure the [local] section is present
echo "Checking and creating [local] section... ${REQUIRED_LOCAL_SECTION}"
add_section_if_not_exists "[local]" "$REQUIRED_LOCAL_SECTION" "${INVENTORY_FILE}"
#check if k3s is enabled
if [ "${K3S_ENABLED}" == "true" ]; then
    # Check if K3S_MASTERS and K3S_NODES are not empty, and then update the inventory file accordingly
    if [ -n "${K3S_MASTERS}" ]; then
        add_hosts "master" "${K3S_MASTERS}"
    fi
    if [ -n "${K3S_NODES}" ]; then
        add_hosts "node" "${K3S_NODES}"
    fi

    # Check if the K3s Cluster is defined 
    # Define the second section you want to ensure is present in the file
    REQUIRED_CLUSTER_SECTION="[k3s_cluster:children]\nmaster\nnode"
    # Ensure the [k3s_cluster:children] section is present
    echo "Checking and creating [k3s_cluster:children] section... ${REQUIRED_CLUSTER_SECTION}"
    add_section_if_not_exists "[k3s_cluster:children]" "$REQUIRED_CLUSTER_SECTION" "${INVENTORY_FILE}"
fi

echo "ANSIBLE_INVENTORY_FILE created."
# Check and create ANSIBLE Group Vars if it doesn't exist
echo "Checking and creating ANSIBLE Group Vars..."
if [ ! -d "${ANSIBLE_INVENTORY_PATH}/group_vars" ]; then
    mkdir -p "${ANSIBLE_INVENTORY_PATH}/group_vars"
fi
if [ ! -f "${ANSIBLE_INVENTORY_PATH}/group_vars/all.yml" ]; then
    cp k3s-ansible/inventory/sample/group_vars/all.yml "${ANSIBLE_INVENTORY_PATH}/group_vars/all.yml" 
fi
echo "ANSIBLE Group Vars created."
# update Ansible User in Group Vars
echo "Updating Ansible User in Group Vars..."
sed -i "s/{{ ansible_user }}/${ANSIBLE_USER}/g" "${ANSIBLE_INVENTORY_PATH}/group_vars/all.yml"
echo "Ansible User updated in Group Vars."

ansible-playbook homelab.yml
