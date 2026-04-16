.#!/bin/bash

source .env

# Combine all hosts into a single array
HOSTS=("$K3S_MASTERS" $(echo "$K3S_NODES" | tr ',' ' '))

# Generate an SSH key if it doesn't already exist
if [[ ! -f ~/.ssh/id_rsa ]]; then
    echo "Generating SSH key..."
    ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
else
    echo "SSH key already exists. Skipping generation."
fi

# Copy the SSH key to each host
for host in "${HOSTS[@]}"; do
    echo "Copying SSH key to $host..."
    ssh-copy-id -i ~/.ssh/id_rsa.pub "$host"
done

echo "SSH key setup completed for all hosts."
