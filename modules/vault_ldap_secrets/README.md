# Module: vault_ldap_secrets — Vault LDAP Secrets Engine

Configures HashiCorp Vault's LDAP secrets engine for Active Directory password rotation and sets up the Kubernetes auth backend used by all secret delivery methods.

This module supports two modes, toggled by `ldap_dual_account`:

| Mode | Plugin | Description |
|------|--------|-------------|
| **Single-account** (`false`) | `vault_ldap_secret_backend` (built-in) | One AD account per static role; standard rotation |
| **Dual-account** (`true`) | Custom `ldap_dual_account` plugin | Blue/green rotation across two AD accounts with a configurable grace period |

## Single-Account Mode (`main.tf`)

- Mounts the built-in LDAP secrets engine at `var.secrets_mount_path` (default: `ldap`)
- Configures LDAPS connection (`insecure_tls = true`) with `schema = ad`, `userattr = cn`
- Creates one static role per entry in `var.static_roles` (map of `{ username, password, dn }`)
- Sets `skip_static_role_import_rotation = false` so Vault rotates on import

## Dual-Account Mode (`dual_account.tf`)

All resources are gated with `count = var.ldap_dual_account ? 1 : 0`.

1. **Registers the custom plugin** — `vault_generic_endpoint` at `sys/plugins/catalog/secret/ldap_dual_account`
2. **Mounts** the custom plugin at `var.secrets_mount_path` as type `ldap_dual_account`
3. **Configures the LDAP backend** via `vault_generic_endpoint` at `<mount>/config`
4. **Creates 3 dual-account static roles:**

| Role Name | Account A | Account B | Used By |
|-----------|-----------|-----------|---------|
| `dual-rotation-demo` | `svc-rotate-a` | `svc-rotate-b` | VSO delivery |
| `vault-agent-dual-role` | `svc-rotate-c` | `svc-rotate-d` | Vault Agent sidecar delivery |
| `csi-dual-role` | `svc-rotate-e` | `svc-rotate-f` | CSI Driver delivery |

5. **Creates 2 single-account static roles** (`svc-single`, `svc-lib`) — the custom plugin also handles standard single-account roles.

Each dual-account role payload:
```json
{
  "username": "svc-rotate-X",
  "dn": "CN=svc-rotate-X,CN=Users,DC=mydomain,DC=local",
  "username_b": "svc-rotate-Y",
  "dn_b": "CN=svc-rotate-Y,CN=Users,DC=mydomain,DC=local",
  "rotation_period": "100s",
  "dual_account_mode": true,
  "grace_period": "20s"
}
```

## Kubernetes Auth Backend (`kubernetes_auth.tf`)

Mounts Vault's Kubernetes auth backend at path `kubernetes` and creates the following roles:

| Role Name | Bound Service Account | Delivery Method | Mode |
|-----------|----------------------|-----------------|------|
| `vso-role` | `vso-auth` | VSO | both |
| `ldap-app-role` | `ldap-app-vault-auth` | VSO (direct polling) | dual-account only |
| `vault-agent-app-role` | `ldap-app-vault-agent` | Vault Agent sidecar | dual-account only |
| `csi-app-role` | `ldap-app-csi` | CSI Driver | dual-account only |

All roles:
- Token TTL: 600s
- Policy: `ldap-static-read` (read `<mount>/static-cred/*`)
- Audience: `vault`

## Policy

`vault_policy.ldap_static_read` — grants `read` on `<mount>/static-cred/*` and `list` on `<mount>/static-role/*`. Named `<mount>-static-read` (e.g., `ldap-static-read`).

## Input Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ldap_url` | string | _(required)_ | LDAP server URL (e.g., `ldaps://10.0.0.5`) |
| `ldap_binddn` | string | `CN=Administrator,CN=Users,DC=mydomain,DC=local` | Vault's bind DN |
| `ldap_bindpass` | string (sensitive) | _(required)_ | Password for the bind account |
| `ldap_userdn` | string | `CN=Users,DC=mydomain,DC=local` | Base DN for user search |
| `secrets_mount_path` | string | `"ldap"` | Vault mount path for the LDAP secrets engine |
| `active_directory_domain` | string | `"mydomain.local"` | AD domain name |
| `static_roles` | map(object) | _(required)_ | Map of `{ username, password, dn }` — used in single-account mode; provided from `AWS_DC` outputs |
| `static_role_rotation_period` | number | `300` | Password rotation interval in seconds |
| `kubernetes_host` | string | _(required)_ | EKS API server endpoint |
| `kubernetes_ca_cert` | string | _(required)_ | Base64-encoded cluster CA cert |
| `kube_namespace` | string | _(required)_ | Kubernetes namespace |
| `ldap_dual_account` | bool | `false` | Enable dual-account rotation mode |
| `grace_period` | number | `15` | Grace period (seconds) during which both accounts are valid |
| `dual_account_static_role_name` | string | `"dual-rotation-demo"` | Name for the VSO dual-account role |
| `plugin_sha256` | string | `e71b4bec...` | SHA256 of the custom plugin binary |

## Outputs

| Output | Description |
|--------|-------------|
| `ldap_secrets_mount_path` | Mount path of the LDAP secrets engine |
| `ldap_secrets_mount_accessor` | Accessor of the LDAP secrets engine |
| `static_role_names` | Map of all created static role names |
| `static_role_policy_name` | Name of the `ldap-static-read` policy |
| `vault_app_auth_role_name` | K8s auth role name for direct app polling (`"ldap-app-role"` in dual-account mode, `""` otherwise) |
