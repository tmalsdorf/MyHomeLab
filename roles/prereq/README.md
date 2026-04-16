# Prereq Role

Sets up prerequisites on localhost and remote nodes including SSH keys, sudoers, and basic packages.

## Requirements

- Target nodes must have package manager (apt)
- SSH access to target nodes

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `local_ssh_public_key` | `~/.ssh/id_rsa` | Path to local SSH public key |

## Dependencies

None

## Example Playbook

```yaml
- hosts: all
  roles:
    - role: prereq
      become: true
```

## License

MIT
