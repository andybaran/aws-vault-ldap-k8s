# Module: vault — Vault Enterprise HA Cluster

Deploys HashiCorp Vault Enterprise in HA Raft mode on EKS, initializes it, and installs the Vault Secrets Operator (VSO) and Secrets Store CSI Driver.

This component runs after `kube1` and is a prerequisite for `vault_ldap_secrets` and `ldap_app`.

## Resources

### Vault Cluster (`vault.tf`)

| Resource | Description |
|----------|-------------|
| `helm_release.vault_cluster` | Vault Helm chart v0.31.0; 3-node HA Raft, TLS disabled, EBS storage (gp3), internet-facing NLBs for API and UI |

**Key Helm values:**

- `server.ha.enabled = true` / `server.ha.raft.enabled = true`
- `server.image` — configurable via `vault_image` variable (default: `hashicorp/vault-enterprise:1.21.2-ent`)
- `server.enterpriseLicense.secretName = vault-license` (created by `kube1`)
- `server.dataStorage` / `server.auditStorage` — 10 GiB EBS gp3 via `vault_storage` StorageClass
- `injector.enabled = true` — Vault Agent injector (sidecar injection via annotations)
- `csi.enabled = true` — Vault CSI Provider daemonset
- `server.service.type = LoadBalancer` — internet-facing NLB for API (port 8200)
- `ui.serviceType = LoadBalancer` — internet-facing NLB for UI (port 8200)

When `ldap_dual_account = true`, the Helm config additionally sets `plugin_directory = "/vault/plugins"` in the Raft storage config to support the custom dual-account LDAP plugin.

### Vault Initialization (`vault_init.tf`)

A Kubernetes Job (`vault-init`) that:
1. Waits for `vault-0` to become ready
2. Runs `vault operator init` (5 key shares, threshold 3)
3. Stores the init JSON (`root_token` + `unseal_keys_b64`) in a K8s Secret (`vault-init-data`)
4. Unseals all 3 Vault nodes
5. Joins `vault-1` and `vault-2` to the Raft cluster

The job is idempotent — if Vault is already initialized it reads the existing `vault-init-data` secret and re-unseals only.

### Vault Secrets Operator (`vso.tf`)

| Resource | Description |
|----------|-------------|
| `helm_release.vault_secrets_operator` | VSO Helm chart v0.9.0 |
| `kubernetes_manifest.vault_connection` | `VaultConnection` CR named `default`; points to Vault's LoadBalancer hostname |
| `kubernetes_manifest.vault_auth` | `VaultAuth` CR named `default`; Kubernetes auth method, role `vso-role`, SA `vso-auth` |
| `kubernetes_service_account_v1.vso` | `vso-auth` ServiceAccount for VSO to authenticate to Vault |
| `kubernetes_cluster_role_binding_v1.vso` | Binds `vso-auth` to `system:auth-delegator` |

### Secrets Store CSI Driver (`csi_driver.tf`)

| Resource | Description |
|----------|-------------|
| `helm_release.secrets_store_csi_driver` | Secrets Store CSI Driver v1.4.7 — only installed when `ldap_dual_account = true` |

Installed with `syncSecret.enabled = true` and `enableSecretRotation = true` (30s poll interval).

### Storage (`storage.tf`)

| Resource | Description |
|----------|-------------|
| `kubernetes_storage_class_v1.vault_storage` | EBS gp3 StorageClass, encrypted, `WaitForFirstConsumer` binding mode |

## Input Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `kube_namespace` | string | _(required)_ | Kubernetes namespace (from `kube1`) |
| `vault_image` | string | `hashicorp/vault-enterprise:1.21.2-ent` | Vault Docker image (`repository:tag`) |
| `ldap_dual_account` | bool | `false` | When `true`: adds `plugin_directory` to Raft config and installs CSI Driver |

## Outputs

| Output | Description |
|--------|-------------|
| `vault_root_token` | Vault root token (non-sensitive — demo only) |
| `vault_unseal_keys` | *(sensitive)* Base64-encoded unseal keys |
| `vault_namespace` | Kubernetes namespace where Vault is deployed |
| `vault_service_name` | Vault service name (`"vault"`) |
| `vault_loadbalancer_hostname` | `http://<LB>:8200` for Vault API |
| `vault_ui_loadbalancer_hostname` | `http://<LB>:8200` for Vault UI |
| `vso_vault_auth_name` | Name of the `VaultAuth` resource (`"default"`) |

## Notes

- **Vault root token is exposed as non-sensitive** — acceptable for demo, not for production.
- The Vault provider used by `vault_ldap_secrets` is configured independently via `var.vault_address` / `var.vault_token` (stored in an HCP Terraform variable set) to avoid Stacks unknown-output dependency issues.
- `kubernetes_deployment_v1` resources in downstream components may trigger "Unexpected Identity Change" errors on the first apply after spec changes — this is transient and resolves on retry.
