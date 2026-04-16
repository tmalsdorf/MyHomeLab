# HomeLab Setup Guide

Quick start: **Clone → Configure → Run**

---

## Step 1: Clone and Prepare

```bash
git clone https://github.com/tmalsdorf/MyHomeLab.git
cd MyHomeLab
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
ansible-galaxy collection install -r collections/requirements.yml
```

---

## Step 2: Configure Your Environment

Copy the example configuration and edit it:

```bash
cp example.env .env
# Edit .env with your preferred editor
```

### Minimum Required Settings

At minimum, you must set:

```bash
# The user Ansible will SSH as (must exist on all nodes)
K3S_USERNAME=ansible

# Enable one environment and set its IPs
K3S_ENABLED_DEV=true
K3S_MASTERS_DEV="192.168.3.50"
K3S_NODES_DEV="192.168.3.51,192.168.3.52,192.168.3.53"
```

### Example: Single Dev Cluster

```bash
K3S_USERNAME=ansible
ENVIRONMENT=dev

K3S_ENABLED_DEV=true
K3S_MASTERS_DEV="192.168.3.50"
K3S_NODES_DEV="192.168.3.51,192.168.3.52,192.168.3.53,192.168.3.54,192.168.3.55"

PORTAINER_ENABLED=true
```

### Example: All Three Environments

```bash
K3S_USERNAME=ansible
SETUP_ALL_ENVIRONMENTS=true

# Dev
K3S_ENABLED_DEV=true
K3S_MASTERS_DEV="192.168.3.50"
K3S_NODES_DEV="192.168.3.51,192.168.3.52"

# UAT
K3S_ENABLED_UAT=true
K3S_MASTERS_UAT="192.168.2.50"
K3S_NODES_UAT="192.168.2.51,192.168.2.52"

# Production
K3S_ENABLED_PROD=true
K3S_MASTERS_PROD="192.168.1.50"
K3S_NODES_PROD="192.168.1.51,192.168.1.52,192.168.1.53"
```

---

## Step 3: Run Setup

### First: Copy SSH Keys (if needed)

If you haven't set up passwordless SSH yet:

```bash
./Copy_ssh_keys.sh
```

This will prompt for passwords and copy your SSH key to all nodes.

### Then: Deploy Your Cluster

```bash
./setup.sh
```

The script will:
1. Create/update inventory files from your `.env` settings
2. Run the Ansible playbook to configure all nodes
3. Set up K3s, ArgoCD, and any enabled services

---

## Working with Multiple Environments

### Setup Mode (creates inventories only)

```bash
# In .env:
SETUP_ALL_ENVIRONMENTS=true

# Then run:
./setup.sh
# Creates: inventory/dev/hosts.ini, inventory/uat/hosts.ini, inventory/prod/hosts.ini
```

### Deploy Specific Environment

```bash
# Deploy just dev
ENVIRONMENT=dev ./setup.sh

# Deploy just production
ENVIRONMENT=prod ./setup.sh
```

---

## Verify Your Cluster

```bash
# Set kubeconfig location (update K3S_USERNAME to match your .env)
export KUBECONFIG=$HOME/.kube/config

# Switch to your environment context
kubectl config use-context dev    # or uat, prod

# Check nodes
kubectl get nodes -o wide

# Check all namespaces
kubectl get namespaces

# Get ArgoCD admin password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
```

---

## Troubleshooting

### Nodes not connecting

- Verify SSH: `ssh ansible@<node-ip>` (should not prompt for password)
- Check network: `ping <node-ip>`
- Verify user exists on nodes: `ssh ansible@<node-ip> "whoami"`

### Ansible playbook fails

- Check inventory: `cat inventory/dev/hosts.ini`
- Test connectivity: `ansible all -i inventory/dev/hosts.ini -m ping`
- Check logs: Run `ansible-playbook -i inventory/dev/hosts.ini homelab.yml -vvv`

### Reset and start over

```bash
./reset.sh  # Resets K3s cluster and removes kubeconfig
```
