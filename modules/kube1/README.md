# Module: kube1 — Kubernetes Base Tools

Installs the Kubernetes-level prerequisites that all later components depend on: the Vault Enterprise license secret, an nginx ingress controller, and the Vault `ServiceAccount` used for token review.

This component runs after `kube0` and before `vault_cluster`.

## Resources

| Resource | Description |
|----------|-------------|
| `kubernetes_secret_v1.vault_license` | Stores the Vault Enterprise license key as a K8s Secret (`vault-license`) |
| `helm_release.nginx_ingress` | nginx Ingress Controller via `ingress-nginx` Helm chart; backed by 3 AWS Elastic IPs for NLB stability |
| `aws_eip` × 3 | Elastic IPs pre-allocated for the nginx NLB to prevent address churn |
| `kubernetes_service_account_v1.vault_auth` | `vault-auth` ServiceAccount used by Vault's Kubernetes auth method for token review |
| `kubernetes_secret_v1.vault_auth_token` | Long-lived token secret bound to `vault-auth` SA |
| `kubernetes_cluster_role_binding_v1.vault_auth` | Binds `vault-auth` SA to `system:auth-delegator` ClusterRole |

## Input Variables

| Variable | Type | Description |
|----------|------|-------------|
| `demo_id` | string | Demo identifier from `kube0` (used for resource tagging) |
| `cluster_endpoint` | string | EKS API server endpoint (from `kube0`) |
| `kube_cluster_certificate_authority_data` | string | Base64-encoded cluster CA (from `kube0`) |
| `vault_license_key` | string | Vault Enterprise license key (from HCP Terraform variable set) |

## Outputs

| Output | Description |
|--------|-------------|
| `kube_namespace` | Kubernetes namespace for all demo resources (hardcoded: `"default"`) |
