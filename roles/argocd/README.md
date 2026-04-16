# ArgoCD Role

Deploys and configures ArgoCD on a Kubernetes cluster (typically K3s).

## Requirements

- Kubernetes cluster with kubectl configured
- Helm 3.x installed (optional, for Helm-based deployments)

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `argocd_action` | `present` | Action to perform: `present` or `absent` |
| `argocd_k8s_namespace` | `argocd` | Kubernetes namespace for ArgoCD |
| `argocd_k8s_service_type` | `LoadBalancer` | Service type for ArgoCD server |
| `argocd_cli_version` | `1.0.2` | ArgoCD CLI version |
| `argocd_admin_name` | `admin` | Admin username |
| `argocd_new_admin_password` | From env `ARGO_PASSWORD` | Admin password |

## Dependencies

- `kubernetes.core` collection

## Example Playbook

```yaml
- hosts: localhost
  roles:
    - role: argocd
      vars:
        argocd_action: present
        argocd_k8s_namespace: argocd
```

## License

MIT
