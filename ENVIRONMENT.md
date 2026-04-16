# Multi-Environment Setup Guide

This repository now supports **Dev**, **UAT**, and **Prod** environments with separate inventories and configurations.

## Quick Start

### 1. Set Your Environment

Edit `.env` and set the `ENVIRONMENT` variable:
```bash
ENVIRONMENT=dev    # or uat, prod
```

### 2. Configure Your Inventory

Update the hosts file for your environment:
```bash
# For dev
vim inventory/dev/hosts.ini

# For UAT
vim inventory/uat/hosts.ini

# For production
vim inventory/prod/hosts.ini
```

Add your host IPs:
```ini
[master]
192.168.1.10 ansible_user=ansible
192.168.1.11 ansible_user=ansible

[node]
192.168.1.20 ansible_user=ansible
192.168.1.21 ansible_user=ansible
```

### 3. Copy Ansible Config

```bash
cp ansible.cfg.example ansible.cfg
```

### 4. Run Setup

```bash
./setup.sh
```

Or run Ansible directly:
```bash
ansible-playbook -i inventory/${ENVIRONMENT}/hosts.ini homelab.yml
```

## Environment Differences

| Feature | Dev | UAT | Prod |
|---------|-----|-----|------|
| **Security** | Relaxed | Moderate | Strict |
| **Firewall** | Off | On | Strict |
| **Debug Mode** | Enabled | Disabled | Disabled |
| **K3s Args** | Basic | Standard | HA + TLS SANs |
| **SSH Host Checking** | No | Yes | Strict |
| **Backups** | Optional | Enabled | Required |
| **Monitoring** | Optional | Enabled | Required |

## Inventory Structure

```
inventory/
├── dev/
│   ├── hosts.ini          # Dev hosts (add your IPs)
│   └── group_vars/
│       └── all.yml        # Dev-specific variables
├── uat/
│   ├── hosts.ini          # UAT hosts
│   └── group_vars/
│       └── all.yml        # UAT-specific variables
├── prod/
│   ├── hosts.ini          # Prod hosts
│   └── group_vars/
│       └── all.yml        # Prod-specific variables
└── example/
    └── group_vars/
        └── all.yml        # Template for new environments
```

## Important Notes

### Security
- **Prod**: Strict SSH host key checking enabled
- **Prod**: Firewall enabled with default DROP policy
- **Prod**: Automatic security updates enabled
- Consider adding `inventory/*/hosts.ini` to `.gitignore` to protect IP addresses

### K3s Configuration
- Dev: Basic setup for testing
- UAT: Standard production-like setup
- Prod: High availability with TLS SANs, etcd tuning

### Running Playbooks

```bash
# Development
ENVIRONMENT=dev ./setup.sh

# UAT
ENVIRONMENT=uat ./setup.sh

# Production (requires explicit confirmation)
ENVIRONMENT=prod ./setup.sh
```

Or manually:
```bash
ansible-playbook -i inventory/dev/hosts.ini homelab.yml
ansible-playbook -i inventory/uat/hosts.ini homelab.yml
ansible-playbook -i inventory/prod/hosts.ini homelab.yml
```

## Adding a New Environment

1. Copy the example structure:
```bash
cp -r inventory/example inventory/myenv
```

2. Create `inventory/myenv/hosts.ini`

3. Update `inventory/myenv/group_vars/all.yml`

4. Set `ENVIRONMENT=myenv` in `.env`

## Best Practices

1. **Always test in Dev first**, then UAT, before Prod
2. **Never commit actual IP addresses** - use environment variables or vault
3. **Use Ansible Vault** for sensitive data in production
4. **Keep prod inventory minimal** - only what's necessary
5. **Document changes** in commit messages when modifying prod vars
6. **Use tags** for targeted deployments: `ansible-playbook -i inventory/prod/hosts.ini homelab.yml --tags deploy_argocd`

## Troubleshooting

### Inventory Not Found
```bash
# Verify inventory path
ansible-inventory -i inventory/dev/hosts.ini --list
```

### Permission Denied
```bash
# Ensure SSH key is set up
ssh-copy-id -i ~/.ssh/id_rsa ansible@<host-ip>
```

### Wrong Environment
```bash
# Check current environment
echo $ENVIRONMENT

# Source the env file
source .env
```
