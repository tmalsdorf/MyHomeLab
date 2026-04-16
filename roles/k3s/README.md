# K3s Role

Installs K3s management tools (kubectl, helm, k3sup) on the control node.

## Requirements

- None (downloads tools as needed)

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `kubectl_version` | Latest | kubectl version to install |
| `helm_version` | Latest | Helm version to install |
| `k3sup_version` | Latest | k3sup version to install |

## Dependencies

None

## Example Playbook

```yaml
- hosts: localhost
  roles:
    - role: k3s
```

## License

MIT
