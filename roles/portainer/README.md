# Portainer Role

Deploys Portainer container management UI on the local Docker/Kubernetes environment.

## Requirements

- Docker or Kubernetes cluster
- Environment variable `PORTAINER_ENABLED=true`

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `portainer_enabled` | From env `PORTAINER_ENABLED` | Whether to deploy Portainer |
| `portainer_port` | `9000` | Port for Portainer UI |

## Dependencies

None

## Example Playbook

```yaml
- hosts: localhost
  roles:
    - role: portainer
```

## License

MIT
