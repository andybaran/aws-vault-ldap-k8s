# Module: ldap_app — LDAP Credentials Application Deployments

Deploys the Python Flask application in three separate Kubernetes Deployments, each demonstrating a different Vault secret delivery method. All three deployments run simultaneously when `ldap_dual_account = true`.

## Delivery Methods

### 1. VSO — Vault Secrets Operator (`ldap_app.tf`)

| Resource | Description |
|----------|-------------|
| `kubernetes_manifest.vault_ldap_secret` | `VaultDynamicSecret` CR that syncs credentials from Vault into K8s Secret `ldap-credentials` |
| `kubernetes_service_account_v1.ldap_app` | `ldap-app-vault-auth` SA for direct Vault API polling (dual-account only) |
| `kubernetes_deployment_v1.ldap_app` | 2-replica deployment; `SECRET_DELIVERY_METHOD=vault-secrets-operator` |
| `kubernetes_service_v1.ldap_app` | LoadBalancer service on port 80 → 8080 |

The `VaultDynamicSecret` CR uses `allowStaticCreds: true` and `refreshAfter` set to 80% of the rotation period for timely credential sync. In dual-account mode, the app also polls Vault directly (using `ldap-app-role`) to display live rotation state and grace period countdown.

**AD accounts:** `svc-rotate-a` (active) / `svc-rotate-b` (standby)

### 2. Vault Agent Sidecar (`vault_agent_app.tf`)

| Resource | Description |
|----------|-------------|
| `kubernetes_service_account_v1.vault_agent` | `ldap-app-vault-agent` SA |
| `kubernetes_config_map_v1.vault_agent_config` | Vault Agent HCL config; uses Consul Template to render credentials to `/vault/secrets/ldap-creds` |
| `kubernetes_deployment_v1.vault_agent_app` | Init container (Vault Agent) + sidecar (Vault Agent) + app container; `SECRET_DELIVERY_METHOD=vault-agent-sidecar` |
| `kubernetes_service_v1.vault_agent_app` | LoadBalancer service on port 80 → 8080 |

Uses a projected ServiceAccount token volume with `audience: "vault"` for Kubernetes auth (required because Vault Agent's `kubernetes` auto_auth does not support `token_audiences`). Authenticates with `vault-agent-app-role`.

**AD accounts:** `svc-rotate-c` (active) / `svc-rotate-d` (standby)

### 3. CSI Driver (`csi_app.tf`)

| Resource | Description |
|----------|-------------|
| `kubernetes_service_account_v1.csi_app` | `ldap-app-csi` SA |
| `kubernetes_manifest.secret_provider_class` | `SecretProviderClass` CR for `csi-dual-role`; mounts the full JSON response + individual fields |
| `kubernetes_deployment_v1.csi_app` | App reads credentials from CSI-mounted files at `/vault/secrets`; `SECRET_DELIVERY_METHOD=vault-csi-driver` |
| `kubernetes_service_v1.csi_app` | LoadBalancer service on port 80 → 8080 |

Uses a projected ServiceAccount token volume for direct Vault API polling alongside the CSI volume. Authenticates with `csi-app-role`.

**AD accounts:** `svc-rotate-e` (active) / `svc-rotate-f` (standby)

## Input Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `kube_namespace` | string | `"default"` | Kubernetes namespace |
| `ldap_mount_path` | string | `"ldap"` | Vault LDAP secrets engine mount path |
| `ldap_static_role_name` | string | `"demo-service-account"` | LDAP static role name (VSO deployment) |
| `vso_vault_auth_name` | string | `"default"` | Name of the `VaultAuth` CR |
| `static_role_rotation_period` | number | `30` | Rotation period in seconds (used to compute VSO `refreshAfter`) |
| `ldap_app_image` | string | `ghcr.io/andybaran/vault-ldap-demo:latest` | Docker image for the app |
| `ldap_dual_account` | bool | `false` | Deploys all 3 delivery methods when `true` |
| `grace_period` | number | `15` | Grace period in seconds for dual-account Consul Template rendering |
| `vault_app_auth_role` | string | `""` | Vault K8s auth role for direct polling (passed to VSO deployment) |
| `vault_agent_image` | string | `hashicorp/vault:1.18.0` | Docker image for the Vault Agent sidecar |

## Outputs

| Output | Description |
|--------|-------------|
| `ldap_app_service_name` | Service name for the VSO deployment |
| `ldap_app_service_type` | Service type (`LoadBalancer`) |
| `ldap_app_url` | HTTP URL of the VSO app LoadBalancer |
| `ldap_app_vault_agent_url` | HTTP URL of the Vault Agent sidecar app LoadBalancer |
| `ldap_app_csi_url` | HTTP URL of the CSI Driver app LoadBalancer |

## Notes

- All three deployments are only created when `ldap_dual_account = true`. In single-account mode only the VSO deployment is created.
- Pod rolling restarts are triggered by VSO on credential rotation (via `rolloutRestartTargets`).
- Resource limits: 200m CPU / 256 Mi memory per container.
