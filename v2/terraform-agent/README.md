# Terraform Agent Documentation

## Implementation Summary

The Terraform agent implemented three secret delivery methods in the `modules/ldap_app/` module.

## Files Created

| File | Purpose |
|------|---------|
| `vault_agent_app.tf` | Vault Agent sidecar deployment for `svc-single` |
| `csi_app.tf` | CSI Driver deployment for `svc-lib` |

## Files Modified

| File | Changes |
|------|---------|
| `ldap_app.tf` | Added `SECRET_DELIVERY_METHOD` env var |
| `variables.tf` | Added `vault_agent_image` variable |
| `kubernetes_auth.tf` | Added `vault-agent-app-role` and `csi-app-role` roles |

## Key Design Decisions

### 1. Manual Sidecar vs Injector Webhook
Chose manual sidecar definition over Vault Agent Injector webhook for:
- More explicit control in demo scenarios
- Clearer Terraform resource visibility
- No dependency on webhook admission controller

### 2. Init Container Pattern
Vault Agent deployment uses init container to pre-render credentials:
- `vault-agent-init`: Runs once with `exit_after_auth = true`
- `vault-agent`: Sidecar that continuously refreshes

### 3. Deployment Guards
All new deployments gated with `count = var.ldap_dual_account ? 1 : 0` to deploy only when dual-account mode is enabled.

## Vault Auth Configuration

```hcl
# modules/vault_ldap_secrets/kubernetes_auth.tf

# Vault Agent role
resource "vault_kubernetes_auth_backend_role" "vault_agent_app" {
  role_name                        = "vault-agent-app-role"
  bound_service_account_names      = ["ldap-app-vault-agent"]
  token_policies                   = ["ldap-static-read"]
}

# CSI role
resource "vault_kubernetes_auth_backend_role" "csi_app" {
  role_name                        = "csi-app-role"
  bound_service_account_names      = ["ldap-app-csi"]
  token_policies                   = ["ldap-static-read"]
}
```
