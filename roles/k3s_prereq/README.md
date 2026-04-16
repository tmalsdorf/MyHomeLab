# K3s Prereq Role

Prepares nodes for K3s installation with required packages and settings.

## Requirements

- Target nodes must have package manager (apt)

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `k3s_enabled` | From env `K3S_ENABLED` | Whether K3s is enabled |

## Dependencies

None

## Example Playbook

```yaml
- hosts: k3s_cluster
  roles:
    - role: k3s_prereq
```

## License

MIT
