# AWS Vault LDAP K8s - Quick Reference Guide

## Critical Inputs/Outputs Flow

### DC Module → vault_ldap_secrets Module (CRITICAL)
```
component.ldap outputs:
├─ dc-priv-ip (e.g., "10.0.1.50")
│  └─ Used in: ldap_url = "ldaps://${component.ldap.dc-priv-ip}"
├─ password (Administrator password)
│  └─ Used in: ldap_bindpass = component.ldap.password
└─ static_roles (map of test users)
   └─ Each role:
      {
        "svc-rotate-a": {
          "username": "svc-rotate-a",
          "password": "Xyz123!@#",
          "dn": "CN=svc-rotate-a,CN=Users,DC=mydomain,DC=local"
        }
      }
   └─ Used in: static_roles = component.ldap.static_roles
```

### vault_cluster Module → vault_ldap_secrets Module
```
component.vault_cluster outputs:
├─ vault_root_token
│  └─ Provider token for vault_ldap_secrets
├─ vault_loadbalancer_hostname
│  └─ Provider address for vault_ldap_secrets
└─ vso_vault_auth_name = "default"
   └─ VaultAuth resource name for VSO
```

### vault_ldap_secrets → ldap_app Module
```
component.vault_ldap_secrets outputs:
├─ ldap_secrets_mount_path = "ldap"
│  └─ Input: ldap_mount_path
├─ vault_app_auth_role_name = "ldap-app-role"
│  └─ Input: vault_app_auth_role (dual-account only)
└─ static_role_names
   └─ Reference: which roles are available
```

---

## Key Variables by Component

### Root Stack (components.tfcomponent.hcl)
```hcl
ldap_dual_account = true|false
├─ Selects vault_image
├─ Selects LDAP engine type (ldap vs ldap_dual_account)
├─ Enables vault_agent_app.tf and csi_app.tf
└─ Affects credential response schema

grace_period = 20
└─ Only used in dual_account mode
   └─ Overlap time when both account credentials are valid

install_adds = true|false
├─ true: Deploy Active Directory Domain Services
└─ false: Plain Windows Server (no LDAP)

install_adcs = true|false
├─ true: Install AD Certificate Services (enables LDAPS on 636)
└─ false: Use ldap:// instead (unencrypted)
```

### AWS_DC Module
```hcl
active_directory_domain = "mydomain.local"
active_directory_netbios_name = "mydomain"

Test accounts created:
├─ svc-rotate-a ↔ svc-rotate-b (dual: demo/VSO)
├─ svc-rotate-c ↔ svc-rotate-d (dual: vault-agent)
├─ svc-rotate-e ↔ svc-rotate-f (dual: csi)
├─ svc-single (single: vault-agent)
└─ svc-lib (single: csi)
```

### vault_ldap_secrets Module
```hcl
# Single-Account Mode (ldap_dual_account=false)
vault_ldap_secret_backend "ad" {
  path = "ldap"
  url = "ldaps://<dc-priv-ip>"
  binddn = "CN=Administrator,CN=Users,DC=mydomain,DC=local"
  bindpass = <from DC>
  schema = "ad"
  userattr = "cn"  # NOT userPrincipalName
  userdn = "CN=Users,DC=mydomain,DC=local"
  insecure_tls = true  # Self-signed ADCS cert
}

# Dual-Account Mode (ldap_dual_account=true)
Plugin Mount:
├─ Type: "ldap_dual_account"
├─ Command: "vault-plugin-secrets-openldap"
├─ Version: "v0.17.0-dual-account.1"
└─ SHA256: "e71b4bec10963fe5f704d710f34be5a933330126799541fd1bd7b0e3536a8dad"

Static Roles:
├─ dual-rotation-demo: svc-rotate-a (primary) ↔ svc-rotate-b (secondary)
│  └─ rotation_period: 100s, grace_period: 20s, dual_account_mode: true
├─ vault-agent-dual-role: svc-rotate-c ↔ svc-rotate-d
├─ csi-dual-role: svc-rotate-e ↔ svc-rotate-f
├─ svc-single: Single account rotation (no dual_account_mode)
└─ svc-lib: Single account rotation (no dual_account_mode)
```

### ldap_app Module
```hcl
# Input variables
ldap_mount_path = "ldap"  # Where LDAP engine is mounted
ldap_static_role_name = "dual-rotation-demo"  # Role to read
vso_vault_auth_name = "default"  # VaultAuth CR name
ldap_dual_account = true|false  # Enable vault-agent & csi deployments

# Service Accounts (dual_account only)
├─ ldap-app-vault-auth (VSO → direct Vault polling)
├─ ldap-app-vault-agent (Vault Agent sidecar)
└─ ldap-app-csi (CSI Driver)

# Deployments created
ldap-credentials-app (VSO) - Always
├─ VaultDynamicSecret CR references: ldap/static-cred/<role>
├─ Synced to K8s secret: ldap-credentials
├─ Replicas: 2
└─ Refresh: ~80% of rotation_period

ldap-app-vault-agent - Dual-account only
├─ Init container + Sidecar (Vault Agent)
├─ Renders to: /vault/secrets/ldap-creds (env format)
├─ Replicas: 1
└─ Refresh: every 30s

ldap-app-csi - Dual-account only
├─ CSI volume mount: /vault/secrets/
├─ Files: username, password, rotation_state, ...
├─ Replicas: 1
└─ JSON response also available: ldap-creds.json
```

---

## Environment Variables by Deployment Method

### VSO Deployment
```
From K8s Secret (LDAP Credentials):
  LDAP_USERNAME=svc-rotate-a
  LDAP_PASSWORD=<password>
  LDAP_LAST_VAULT_PASSWORD=<last_rotation_timestamp>
  ROTATION_PERIOD=100
  ROTATION_TTL=<ttl_value>

Dual-Account Fields (optional, grace_period only):
  ACTIVE_ACCOUNT=primary|secondary
  ROTATION_STATE=active|grace_period
  STANDBY_USERNAME=svc-rotate-b (during grace_period)
  STANDBY_PASSWORD=<password_b> (during grace_period)
  GRACE_PERIOD_END=<iso_timestamp> (during grace_period)

Hardcoded:
  SECRET_DELIVERY_METHOD=vault-secrets-operator
  DUAL_ACCOUNT_MODE=true (if enabled)
  GRACE_PERIOD=20
```

### Vault Agent Sidecar
```
From File (/vault/secrets/ldap-creds, env format):
  LDAP_USERNAME=svc-rotate-c
  LDAP_PASSWORD=<password>
  [same fields as VSO]

Hardcoded:
  SECRET_DELIVERY_METHOD=vault-agent-sidecar
  SECRETS_FILE_PATH=/vault/secrets/ldap-creds
  DUAL_ACCOUNT_MODE=true
  VAULT_ADDR=http://vault.vso.svc.cluster.local:8200
  VAULT_AUTH_ROLE=vault-agent-app-role
  LDAP_MOUNT_PATH=ldap
  LDAP_STATIC_ROLE_NAME=vault-agent-dual-role
```

### CSI Driver
```
From Files (/vault/secrets/*, individual files):
  username → File: /vault/secrets/username
  password → File: /vault/secrets/password
  rotation_state → File: /vault/secrets/rotation_state
  active_account → File: /vault/secrets/active_account
  [etc.]

Full JSON Response:
  /vault/secrets/ldap-creds.json

Hardcoded:
  SECRET_DELIVERY_METHOD=vault-csi-driver
  SECRETS_FILE_PATH=/vault/secrets
  DUAL_ACCOUNT_MODE=true
  VAULT_ADDR=http://vault.vso.svc.cluster.local:8200
  VAULT_AUTH_ROLE=csi-app-role
  LDAP_MOUNT_PATH=ldap
  LDAP_STATIC_ROLE_NAME=csi-dual-role
```

---

## Kubernetes Auth Roles

### VSO Mode
```
Auth Backend: kubernetes
Mount Path: /auth/kubernetes

Role: vso-role
├─ Service Account: vso-auth
├─ Namespace: vso
├─ Token TTL: 600s
└─ Policies: [ldap-static-read]
```

### Dual-Account Mode (Additional Roles)
```
Role: ldap-app-role
├─ Service Account: ldap-app-vault-auth
├─ Used by: LDAP app for direct Vault polling
└─ Policies: [ldap-static-read]

Role: vault-agent-app-role
├─ Service Account: ldap-app-vault-agent
├─ Used by: Vault Agent init/sidecar
└─ Policies: [ldap-static-read]

Role: csi-app-role
├─ Service Account: ldap-app-csi
├─ Used by: CSI Driver
└─ Policies: [ldap-static-read]
```

---

## Vault Plugin Plugin Directory

When `ldap_dual_account=true`:
```
Helm Values:
  server.ha.raft.config includes:
    plugin_directory = "/vault/plugins"

This allows Vault to load custom plugins from:
  /vault/plugins/vault-plugin-secrets-openldap

Custom Image:
  ghcr.io/andybaran/vault-with-openldap-plugin:dual-account-rotation
  └─ Must have plugin binary in /vault/plugins/
```

---

## Dual-Account Rotation States

### State: ACTIVE
```json
{
  "username": "svc-rotate-a",
  "password": "current_password_123",
  "active_account": "primary",
  "rotation_state": "active",
  "last_vault_rotation": "2024-01-15T10:30:00Z",
  "rotation_period": "100",
  "ttl": "99",
  "dual_account_mode": true
}
```
Note: No standby fields present

### State: GRACE_PERIOD
```json
{
  "username": "svc-rotate-a",
  "password": "current_password_123",
  "standby_username": "svc-rotate-b",
  "standby_password": "new_password_456",
  "active_account": "primary",
  "rotation_state": "grace_period",
  "grace_period_end": "2024-01-15T10:30:20Z",
  "last_vault_rotation": "2024-01-15T10:30:00Z",
  "rotation_period": "100",
  "ttl": "95",
  "dual_account_mode": true
}
```
Note: Both accounts present, grace_period_end timestamp set

### State After Grace Period Expires
```json
{
  "username": "svc-rotate-b",
  "password": "new_password_456",
  "active_account": "secondary",
  "rotation_state": "active",
  ...
}
```
Roles have switched; secondary becomes new primary

---

## LDAP Configuration Summary

```
Connection Details:
├─ URL: ldaps://10.0.1.50:636 (dc-priv-ip from AWS_DC module)
├─ Schema: ad (Active Directory)
├─ Bind DN: CN=Administrator,CN=Users,DC=mydomain,DC=local
├─ Bind Password: <from DC module>
└─ User Search Base: CN=Users,DC=mydomain,DC=local

User Search:
├─ Attribute: cn (NOT userPrincipalName)
└─ Reason: Vault searches with bare username (svc-rotate-a)

Certificate:
├─ Type: Self-signed from AD Certificate Services
├─ Verification: insecure_tls=true (dev only)
└─ Prerequisite: install_adcs=true on DC

Test Users Created on DC:
├─ svc-rotate-a (CN=svc-rotate-a,CN=Users,DC=mydomain,DC=local)
├─ svc-rotate-b
├─ svc-rotate-c
├─ svc-rotate-d
├─ svc-rotate-e
├─ svc-rotate-f
├─ svc-single
└─ svc-lib
   └─ All get random 16-char passwords with special chars
```

---

## Dependency Chain Summary

```
AWS_DC (Windows Server 2025)
  ↓ [dc-priv-ip, password, static_roles]
vault_ldap_secrets (LDAP Engine)
  ↓ [ldap_secrets_mount_path, vault_app_auth_role_name]
ldap_app (Apps)
  ├─ ldap-credentials-app (VSO)
  ├─ ldap-app-vault-agent (Vault Agent)
  └─ ldap-app-csi (CSI Driver)

Also Required:
├─ vault_cluster (Vault server)
│  └─ [vault_root_token, vault_loadbalancer_hostname, vso_vault_auth_name]
├─ kube0 (EKS cluster)
├─ kube1 (K8s namespace)
└─ Kubernetes Auth Backend (in vault_ldap_secrets)
```

---

## Single vs Dual-Account Comparison

| Aspect | Single-Account | Dual-Account |
|--------|---|---|
| Vault Mount Type | ldap | ldap_dual_account |
| Plugin Required | No | Yes (custom) |
| Accounts per Role | 1 | 2 (primary + secondary) |
| Password Override | Immediate | With grace period |
| Response Fields | username, password | + active_account, rotation_state, standby_username, standby_password, grace_period_end |
| Rotation Behavior | Stop old, set new | Overlap both, then switch |
| App Deployments | VSO only | VSO + Vault Agent + CSI |
| Use Case | Simple rotation | Zero-downtime password changes |
| Custom Image | Standard Vault | ghcr.io/.../vault-with-openldap-plugin |

