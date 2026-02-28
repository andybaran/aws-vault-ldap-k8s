# Research Findings: Secret Delivery Methods

## Date: 2026-02-28 | Updated: 2026-03-01

## Status: ✅ COMPLETE

All three secret delivery methods are implemented and deployed.

---

## Key Findings

### 1. Current Vault Helm Configuration
- ✅ **CSI Provider**: ENABLED (`csi.enabled = true`) in `modules/vault/vault.tf`
- ✅ **Agent Injector**: Disabled — using manual sidecar approach instead (more control for demos)
- ✅ **Secrets Store CSI Driver**: Installed separately via Helm in `modules/kube1/`

### 2. AD Service Account Allocation
| Account | Delivery Method | Mode | Status |
|---------|----------------|------|--------|
| svc-rotate-a + svc-rotate-b | VSO (VaultDynamicSecret) | Dual-account | ✅ Deployed |
| svc-single | Vault Agent Sidecar | Single-account | ✅ Deployed |
| svc-lib | CSI Driver | Single-account | ✅ Deployed |

### 3. Static Roles Configuration
- ✅ Dual-account static roles created via custom `ldap_dual_account` plugin
- ✅ Single-account roles for `svc-single` and `svc-lib` created on same LDAP mount
- ✅ Kubernetes auth roles configured for all three delivery methods

### 4. Python App Refactoring
- ✅ File-based credential reading implemented for Vault Agent and CSI modes
- ✅ `SECRET_DELIVERY_METHOD` env var determines display mode
- ✅ Same Docker image (`ghcr.io/andybaran/vault-ldap-demo:latest`) used for all deployments
- ✅ `SECRETS_FILE_PATH` env var configures credential file location

### 5. Secrets Store CSI Driver
- ✅ CSI Driver installed via `secrets-store-csi-driver` Helm chart in `modules/kube1/`
- ✅ Vault CSI Provider enabled in Vault Helm values
- ✅ `SecretProviderClass` CR created for `svc-lib` credentials

### 6. Vault Agent Implementation
- ✅ Manual sidecar definition in Terraform (more control for demos)
- ✅ Init container pre-renders credentials before app starts
- ✅ Sidecar container refreshes credentials every 30s
- ✅ Credentials rendered to `/vault/secrets/ldap-creds` as key=value file

---

## Implementation Files

| Delivery Method | Terraform File | K8s Resources |
|-----------------|----------------|---------------|
| VSO | `modules/ldap_app/ldap_app.tf` | VaultDynamicSecret, Deployment, Service |
| Vault Agent | `modules/ldap_app/vault_agent_app.tf` | ConfigMap, Deployment (init+sidecar), Service |
| CSI Driver | `modules/ldap_app/csi_app.tf` | SecretProviderClass, Deployment, Service |

## Vault Auth Roles

| Role Name | Service Account | Used By |
|-----------|-----------------|---------|
| `vso-role` | `vso-auth` | VSO (VaultDynamicSecret) |
| `ldap-app-role` | `ldap-app-vault-auth` | VSO direct polling (dual-account) |
| `vault-agent-app-role` | `ldap-app-vault-agent` | Vault Agent sidecar |
| `csi-app-role` | `ldap-app-csi` | CSI Driver |
