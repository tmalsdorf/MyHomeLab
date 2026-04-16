#!/bin/bash

load_env_file() {
    if [ ! -f ".env" ]; then
        echo ".env file not found!"
        exit 1
    fi

    # Export variables from .env file
    export $(grep -v '^#' .env | xargs)

    # Validate required variables based on enabled configurations
    if [[ "$ANSIBLE_ENABLED" == "true" ]]; then
        REQUIRED_ANSIBLE_VARS=(
            ANSIBLE_CONFIG_FILE
            ANSIBLE_TIMEOUT
            ANSIBLE_ROLES_PATH
            ANSIBLE_RETRY_FILES_ENABLED
            ANSIBLE_HOST_KEY_CHECKING
            ANSIBLE_REMOTE_USER
            ANSIBLE_INVENTORY
            ANSIBLE_BECOME_ASK_PASS
            ANSIBLE_BECOME_USER
            ANSIBLE_BECOME_METHOD
            ANSIBLE_BECOME
        )
        for var in "${REQUIRED_ANSIBLE_VARS[@]}"; do
            if [ -z "${!var}" ]; then
                echo "Error: Missing required Ansible variable '$var' in .env file."
                exit 1
            fi
        done
    fi

    if [[ "$ANSIBLE_GROUP_VARS_ENABLED" == "true" ]]; then
        REQUIRED_GROUP_VARS=(
            ANSIBLE_GROUP_VARS_K3S_VERSION
            ANSIBLE_GROUP_VARS_ANSIBLE_USER
            ANSIBLE_GROUP_VARS_SYSTEMD_DIR
            ANSIBLE_GROUP_VARS_SYSTEM_TIMEZONE
            ANSIBLE_GROUP_VARS_FLANNEL_IFACE
            ANSIBLE_GROUP_VARS_APISERVER_ENDPOINT
            ANSIBLE_GROUP_VARS_K3S_TOKEN
            #ANSIBLE_GROUP_VARS_K3S_NODE_IP
            #ANSIBLE_GROUP_VARS_K3S_MASTER_TAINT
            #ANSIBLE_GROUP_VARS_EXTRA_ARGS
            #ANSIBLE_GROUP_VARS_EXTRA_SERVER_ARGS
            #ANSIBLE_GROUP_VARS_EXTRA_AGENT_ARGS
            ANSIBLE_GROUP_VARS_KUBE_VIP_TAG_VERSION
            ANSIBLE_GROUP_VARS_METAL_LB_TYPE
            ANSIBLE_GROUP_VARS_METAL_LB_MODE
            ANSIBLE_GROUP_VARS_METAL_LB_IP_RANGE
            ANSIBLE_GROUP_VARS_METAL_LB_SPEAKER_TAG_VERSION
            ANSIBLE_GROUP_VARS_METAL_LB_CONTROLLER_TAG_VERSION
        )
        for var in "${REQUIRED_GROUP_VARS[@]}"; do
            if [ -z "${!var}" ]; then
                echo "Error: Missing required Group Vars variable '$var' in .env file."
                exit 1
            fi
        done
    fi

    if [[ "$K3S_ENABLED" == "true" ]]; then
        REQUIRED_K3S_VARS=(
            K3S_MASTERS
            K3S_NODES
        )
        for var in "${REQUIRED_K3S_VARS[@]}"; do
            if [ -z "${!var}" ]; then
                echo "Error: Missing required K3S variable '$var' in .env file."
                exit 1
            fi
        done
    fi
}

# Function to add hosts to the inventory file
add_hosts() {
    local section=$1
    local ips=(${2//,/ })
    echo "Adding hosts to $ANSIBLE_INVENTORY for $section section: ${ips[*]}"
    # Check if the section exists, if not, add it
    if ! grep -q "^\[${section}\]$" "${ANSIBLE_INVENTORY}"; then
        echo "[${section}]" >> "${ANSIBLE_INVENTORY}"
    fi

    # Add IPs to the section if they're not already present
    for ip in "${ips[@]}"; do
        # This searches from the current section header until the next section header or EOF
        # and checks if the IP is already present
        if ! sed -n "/^\[${section}\]$/,/^\[.*\]$/p" "${ANSIBLE_INVENTORY}" | grep -q "^${ip}$"; then
            # Insert IPs before the next section starts or at the end of the file
            sed -i "/^\[${section}\]$/a ${ip}" "${ANSIBLE_INVENTORY}"
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
        
    else
        echo "The section $section already exists in $file."
    fi
}

# Function to check and enable passwordless SSH
enable_ssh_access() {
  local host=$1
  #echo "Checking SSH access for $ANSIBLE_REMOTE_USER on $host..."
  sshpass -p "$SSH_PASSWORD" ssh -o BatchMode=yes -o ConnectTimeout=5 "$ANSIBLE_REMOTE_USER@$host" 'exit' 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "Passwordless SSH not enabled on $host. Enabling now..."
    # Copy the SSH key to the remote host
    sshpass -p "$SSH_PASSWORD" ssh-copy-id "$ANSIBLE_REMOTE_USER@$host"
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
  #echo "Checking passwordless sudo access for $ANSIBLE_REMOTE_USER on $host..."
  ssh "$ANSIBLE_REMOTE_USER@$host" "echo '$SUDO_PASSWORD' | sudo -S -n true" 2>/dev/null
  if [ $? -ne 0 ]; then
    #echo "Passwordless sudo not enabled on $host. Enabling now..."
    local sudo_file="/etc/sudoers.d/010-$ANSIBLE_REMOTE_USER-nopassword"
    ssh "$ANSIBLE_REMOTE_USER@$host" "echo '$SUDO_PASSWORD' | sudo -S bash -c 'echo \"$ANSIBLE_REMOTE_USER ALL=(ALL) NOPASSWD: ALL\" > $sudo_file'"
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

generate_ansible_cfg() {
    local ansible_cfg="${ANSIBLE_CONFIG_FILE:-ansible.cfg}"

    # Create a temporary variable to hold the new contents
    local cfg_content=""

    # Only add values if they are set in the .env file

    if [[ -n "$ANSIBLE_TIMEOUT" ]]; then
        cfg_content+="timeout = $ANSIBLE_TIMEOUT"$'\n'
    fi

    if [[ -n "$ANSIBLE_ROLES_PATH" ]]; then
        cfg_content+="roles_path = $ANSIBLE_ROLES_PATH"$'\n'
    fi

    if [[ -n "$ANSIBLE_RETRY_FILES_ENABLED" ]]; then
        cfg_content+="retry_files_enabled = $ANSIBLE_RETRY_FILES_ENABLED"$'\n'
    fi

    if [[ -n "$ANSIBLE_HOST_KEY_CHECKING" ]]; then
        cfg_content+="host_key_checking = $ANSIBLE_HOST_KEY_CHECKING"$'\n'
    fi

    if [[ -n "$ANSIBLE_REMOTE_USER" ]]; then
        cfg_content+="remote_user = $ANSIBLE_REMOTE_USER"$'\n'
    fi

    if [[ -n "$ANSIBLE_INVENTORY" ]]; then
        cfg_content+="inventory = $ANSIBLE_INVENTORY"$'\n'
    fi

    if [[ -n "$ANSIBLE_BECOME_ASK_PASS" || -n "$ANSIBLE_BECOME_USER" || -n "$ANSIBLE_BECOME_METHOD" || -n "$ANSIBLE_BECOME" ]]; then
        cfg_content+=$'\n[privilege_escalation]\n'

        if [[ -n "$ANSIBLE_BECOME_ASK_PASS" ]]; then
            cfg_content+="become_ask_pass = $ANSIBLE_BECOME_ASK_PASS"$'\n'
        fi

        if [[ -n "$ANSIBLE_BECOME_USER" ]]; then
            cfg_content+="become_user = $ANSIBLE_BECOME_USER"$'\n'
        fi

        if [[ -n "$ANSIBLE_BECOME_METHOD" ]]; then
            cfg_content+="become_method = $ANSIBLE_BECOME_METHOD"$'\n'
        fi

        if [[ -n "$ANSIBLE_BECOME" ]]; then
            cfg_content+="become = $ANSIBLE_BECOME"$'\n'
        fi
    fi

    # If no values from .env are set, exit
    if [[ -z "$cfg_content" ]]; then
        echo "No valid variables were found in .env to update ansible.cfg. Exiting."
        return 1
    fi

    # If ansible.cfg exists, update the values
    if [[ -f $ansible_cfg ]]; then
        echo "ansible.cfg exists. Updating values..."
        
        # Update existing values only if they are found in the .env file
        [[ -n "$ANSIBLE_TIMEOUT" ]] && sed -i '/\[defaults\]/,/^\[/ s/^timeout = .*/timeout = '"$ANSIBLE_TIMEOUT"'/' $ansible_cfg
        [[ -n "$ANSIBLE_ROLES_PATH" ]] && sed -i '/\[defaults\]/,/^\[/ s/^roles_path = .*/roles_path = '"$ANSIBLE_ROLES_PATH"'/' $ansible_cfg
        [[ -n "$ANSIBLE_RETRY_FILES_ENABLED" ]] && sed -i '/\[defaults\]/,/^\[/ s/^retry_files_enabled = .*/retry_files_enabled = '"$ANSIBLE_RETRY_FILES_ENABLED"'/' $ansible_cfg
        [[ -n "$ANSIBLE_HOST_KEY_CHECKING" ]] && sed -i '/\[defaults\]/,/^\[/ s/^host_key_checking = .*/host_key_checking = '"$ANSIBLE_HOST_KEY_CHECKING"'/' $ansible_cfg
        [[ -n "$ANSIBLE_REMOTE_USER" ]] && sed -i '/\[defaults\]/,/^\[/ s/^remote_user = .*/remote_user = '"$ANSIBLE_REMOTE_USER"'/' $ansible_cfg
        echo "normal6"
        [[ -n "$ANSIBLE_INVENTORY" ]] && sed -i '/\[defaults\]/,/^\[/ s/^inventory = .*/inventory = '"$ANSIBLE_INVENTORY"'/' $ansible_cfg

        # Update privilege escalation values
        [[ -n "$ANSIBLE_BECOME_ASK_PASS" ]] && sed -i '/\[privilege_escalation\]/,/^\[/ s/^become_ask_pass = .*/become_ask_pass = '"$ANSIBLE_BECOME_ASK_PASS"'/' $ansible_cfg
        [[ -n "$ANSIBLE_BECOME_USER" ]] && sed -i '/\[privilege_escalation\]/,/^\[/ s/^become_user = .*/become_user = '"$ANSIBLE_BECOME_USER"'/' $ansible_cfg
        [[ -n "$ANSIBLE_BECOME_METHOD" ]] && sed -i '/\[privilege_escalation\]/,/^\[/ s/^become_method = .*/become_method = '"$ANSIBLE_BECOME_METHOD"'/' $ansible_cfg
        [[ -n "$ANSIBLE_BECOME" ]] && sed -i '/\[privilege_escalation\]/,/^\[/ s/^become = .*/become = '"$ANSIBLE_BECOME"'/' $ansible_cfg

    else
        # Create the ansible.cfg with the content from the .env variables
        echo "ansible.cfg does not exist. Creating file..."
        echo "[defaults]" > $ansible_cfg
        echo "$cfg_content" >> $ansible_cfg
    fi

    echo "ansible.cfg has been updated or created successfully."
}

# Function to create or update group_vars/all.yml
generate_ansible_group_vars() {
    
    local output_file_path="$ANSIBLE_GROUP_VARS_OUTPUT_DIR/$ANSIBLE_GROUP_VARS_OUTPUT_FILE"
        
    local -A vars=(
        [k3s_version]=$ANSIBLE_GROUP_VARS_K3S_VERSION
        [ansible_user]=$ANSIBLE_GROUP_VARS_ANSIBLE_USER
        [systemd_dir]=$ANSIBLE_GROUP_VARS_SYSTEMD_DIR
        [system_timezone]=$ANSIBLE_GROUP_VARS_SYSTEM_TIMEZONE
        [flannel_iface]=$ANSIBLE_GROUP_VARS_FLANNEL_IFACE
        [apiserver_endpoint]=$ANSIBLE_GROUP_VARS_APISERVER_ENDPOINT
        [k3s_token]=$ANSIBLE_GROUP_VARS_K3S_TOKEN
        #[k3s_node_ip]=$ANSIBLE_GROUP_VARS_K3S_NODE_IP
        #[k3s_master_taint]=$ANSIBLE_GROUP_VARS_K3S_MASTER_TAINT
        #[extra_args]=$ANSIBLE_GROUP_VARS_EXTRA_ARGS
        #[extra_server_args]=$ANSIBLE_GROUP_VARS_EXTRA_SERVER_ARGS
        #[extra_agent_args]=$ANSIBLE_GROUP_VARS_EXTRA_AGENT_ARGS
        [kube_vip_tag_version]=$ANSIBLE_GROUP_VARS_KUBE_VIP_TAG_VERSION
        [metal_lb_type]=$ANSIBLE_GROUP_VARS_METAL_LB_TYPE
        [metal_lb_mode]=$ANSIBLE_GROUP_VARS_METAL_LB_MODE
        [metal_lb_ip_range]=$ANSIBLE_GROUP_VARS_METAL_LB_IP_RANGE
        [metal_lb_speaker_tag_version]=$ANSIBLE_GROUP_VARS_METAL_LB_SPEAKER_TAG_VERSION
        [metal_lb_controller_tag_version]=$ANSIBLE_GROUP_VARS_METAL_LB_CONTROLLER_TAG_VERSION
    )
         
    if [ ! -f "$output_file_path" ]; then
        echo "group_vars/all.yml does not exist. Creating file..."
        mkdir -p "$(dirname "$output_file_path")"
        printf '%s\n' '---' > "$output_file_path"
        for var in "${!vars[@]}"; do
            #echo "Adding $var: ${vars[$var]} to $output_file_path"
            printf '%s: %s\n' "$var" \""${vars[$var]}\"" >> "$output_file_path"
        done
    else
        echo "group_vars/all.yml already exists. Updating..."
        #iterate through the variables update if they exist add if they don't
        for var in "${!vars[@]}"; do
            if grep -q "^$var:" "$output_file_path"; then
                #echo "Updating $var: ${vars[$var]} in $output_file_path"
                sed -i "/^$var:/c $var: \"${vars[$var]}\"" "$output_file_path"
            else
                #echo "Adding $var: ${vars[$var]} to $output_file_path"
                printf '%s: %s\n' "$var" \""${vars[$var]}\"" >> "$output_file_path"
            fi
            
        done
    fi
}

Update_hosts_file_k3s() {
    # Extract master and node IPs
    master_ip="$K3S_MASTERS"
    node_ips="$K3S_NODES"

    # Use the add_hosts function to add the master and node IPs
    echo "Adding Master IPs to $ANSIBLE_INVENTORY..."
    add_hosts "master" "$master_ip"

    echo "Adding Node IPs to $ANSIBLE_INVENTORY..."
    add_hosts "node" "$node_ips"

    # Add the [k3s_cluster:children] section
    cluster_section="[k3s_cluster:children]"
    cluster_content="[k3s_cluster:children]\nmaster\nnode"
    add_section_if_not_exists "$cluster_section" "$cluster_content" "$ANSIBLE_INVENTORY"
    
    echo "Updated $ANSIBLE_INVENTORY successfully for k3s."
}


load_env_file


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

# Check if ANSIBLE_ENABLED is true
if [ "$ANSIBLE_ENABLED" != "true" ]; then
    echo "Ansible is not enabled."
    return
else
    echo "Ansible is enabled."
    echo "Checking ansible.cfg..."
    generate_ansible_cfg
    if [ ! -f "$ANSIBLE_INVENTORY" ]; then
        echo "Inventory file does not exist. Creating... $ANSIBLE_INVENTORY"
        touch "$ANSIBLE_INVENTORY"
    fi
    REQUIRED_LOCAL_SECTION="[local]\nlocalhost ansible_connection=local ansible_user=${ANSIBLE_REMOTE_USER}"
    # Ensure the [local] section is present
    echo "Checking and creating [local] section... ${REQUIRED_LOCAL_SECTION}"
    add_section_if_not_exists "[local]" "$REQUIRED_LOCAL_SECTION" "${ANSIBLE_INVENTORY}"
fi

# Check if ANSIBLE_GROUP_VARS_ENABLED is true
if [ "$ANSIBLE_GROUP_VARS_ENABLED" != "true" ]; then
    echo "Ansible Group Vars is not enabled."
    return
else
    echo "Ansible Group Vars is enabled."
    echo "Checking group_vars/all.yml..."
    generate_ansible_group_vars
fi

#check if k3s is enabled
if [ "${K3S_ENABLED}" == "true" ]; then
    echo "K3S is enabled."
    echo "Checking hosts.ini..."
    Update_hosts_file_k3s
else
    echo "K3S is not enabled."
fi


# Prompt the user for SSH and sudo passwords
read -sp "Enter SSH password for $ANSIBLE_USER: " SSH_PASSWORD
echo
read -sp "Enter sudo password for $ANSIBLE_USER: " SUDO_PASSWORD
echo

# Extract the hosts from the [master] and [node] sections
hosts=$(sed -n '/^\[master\]/,/^\[/p;/^\[node\]/,/^\[/p' "$ANSIBLE_INVENTORY" | grep -E '^\s*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | awk '{print $1}')

# Iterate through the extracted hosts
for host in $hosts; do
  enable_ssh_access "$host"
  enable_sudo_access "$host"
done

ansible-playbook homelab.yml

sleep 30

kubectl get namespaces
kubectl get nodes
kubectl get all --namespace argocd|grep argocd-server
echo "Argocd admin password "
kubectl get secret argocd-initial-admin-secret  --namespace argocd -o yaml|grep password| cut -d' ' -f4|base64 -d
echo ""
