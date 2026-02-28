# V2: Multi-Method Vault Secret Delivery Demo

This demo showcases **three different Vault secret delivery methods** running side-by-side, each displaying rotating LDAP/Active Directory credentials in a web UI.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              EKS Cluster                                    │
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                         Vault HA Cluster (Raft)                        │ │
│  │                                                                        │ │
│  │   ┌─────────────────┐                                                  │ │
│  │   │  LDAP Secrets   │  mount: ldap/                                    │ │
│  │   │     Engine      │  static-cred/svc-rotate-a (dual-account)         │ │
│  │   │                 │  static-cred/svc-single                          │ │
│  │   │                 │  static-cred/svc-lib                             │ │
│  │   └─────────────────┘                                                  │ │
│  │                                                                        │ │
│  │   ┌─────────────────┐                                                  │ │
│  │   │  Kubernetes     │  auth/kubernetes                                 │ │
│  │   │  Auth Backend   │  roles: vso-role, vault-agent-app-role,          │ │
│  │   │                 │         csi-app-role                             │ │
│  │   └─────────────────┘                                                  │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐          │
│  │  VSO Deployment  │  │ Vault Agent      │  │  CSI Deployment  │          │
│  │  (2 replicas)    │  │ Sidecar (1 rep)  │  │  (1 replica)     │          │
│  │                  │  │                  │  │                  │          │
│  │  Account:        │  │  Account:        │  │  Account:        │          │
│  │  svc-rotate-a/b  │  │  svc-single      │  │  svc-lib         │          │
│  │  (dual-account)  │  │  (single-acct)   │  │  (single-acct)   │          │
│  │                  │  │                  │  │                  │          │
│  │  LoadBalancer    │  │  LoadBalancer    │  │  LoadBalancer    │          │
│  │  :80 → :8080     │  │  :80 → :8080     │  │  :80 → :8080     │          │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Active Directory Domain Controller                        │
│                         (Windows Server 2022)                                │
│                                                                             │
│   mydomain.local                                                            │
│   Service Accounts: svc-rotate-a, svc-rotate-b, svc-single, svc-lib         │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Secret Delivery Methods

| Method | App Name | AD Account(s) | How It Works |
|--------|----------|---------------|--------------|
| **VSO** | `ldap-credentials-app` | svc-rotate-a/b | VaultDynamicSecret CR syncs to K8s Secret → env vars |
| **Vault Agent** | `ldap-app-vault-agent` | svc-single | Init + sidecar containers render file at `/vault/secrets/ldap-creds` |
| **CSI Driver** | `ldap-app-csi` | svc-lib | SecretProviderClass mounts files at `/vault/secrets/` |

## Accessing the Applications

After deployment, get the LoadBalancer URLs from Terraform outputs:

```bash
# From HCP Terraform UI or CLI
tfstacks output ldap_app_access_info       # VSO app
tfstacks output ldap_app_vault_agent_url   # Vault Agent app  
tfstacks output ldap_app_csi_url           # CSI app
```

Or via kubectl:

```bash
kubectl get svc -l app=ldap-credentials-app   # VSO
kubectl get svc -l app=ldap-app-vault-agent   # Vault Agent
kubectl get svc -l app=ldap-app-csi           # CSI
```

## Environment Variables

All three deployments use the **same Docker image** (`ghcr.io/andybaran/vault-ldap-demo:latest`). The delivery method is differentiated by environment variables:

| Env Var | VSO | Vault Agent | CSI |
|---------|-----|-------------|-----|
| `SECRET_DELIVERY_METHOD` | `vault-secrets-operator` | `vault-agent-sidecar` | `vault-csi-driver` |
| `SECRETS_FILE_PATH` | — | `/vault/secrets/ldap-creds` | `/vault/secrets` |
| `LDAP_USERNAME` | from K8s Secret | from file | from file |
| `LDAP_PASSWORD` | from K8s Secret | from file | from file |
| `ROTATION_PERIOD` | from K8s Secret | from file | from file |
| `ROTATION_TTL` | from K8s Secret | from file | from file |
| `DUAL_ACCOUNT_MODE` | `true` | — | — |

### File Formats

**Vault Agent** renders a single key=value file:
```
LDAP_USERNAME=svc-single
LDAP_PASSWORD=<rotated-password>
LDAP_LAST_VAULT_PASSWORD=<timestamp>
ROTATION_PERIOD=100
ROTATION_TTL=95
```

**CSI Driver** creates individual files per secret key:
```
/vault/secrets/
├── username         # contains: svc-lib
├── password         # contains: <rotated-password>
├── last_vault_rotation
├── rotation_period
└── ttl
```

## Terraform Resources

### Module: `modules/ldap_app/`

| File | Resources |
|------|-----------|
| `ldap_app.tf` | VaultDynamicSecret, Deployment (VSO), Service |
| `vault_agent_app.tf` | ServiceAccount, ConfigMap, Deployment (init+sidecar), Service |
| `csi_app.tf` | ServiceAccount, SecretProviderClass, Deployment, Service |

### Module: `modules/vault_ldap_secrets/`

| File | Resources |
|------|-----------|
| `kubernetes_auth.tf` | K8s auth backend, roles for VSO/Agent/CSI |
| `main.tf` | LDAP secrets engine, static roles (single-account mode) |
| `dual_account.tf` | Custom plugin mount, dual-account static role |

## Vault Auth Roles

| Role | Service Account | Policy | Used By |
|------|-----------------|--------|---------|
| `vso-role` | `vso-auth` | `ldap-static-read` | VSO controller |
| `vault-agent-app-role` | `ldap-app-vault-agent` | `ldap-static-read` | Vault Agent sidecar |
| `csi-app-role` | `ldap-app-csi` | `ldap-static-read` | CSI Provider |

## Rotation Configuration

| Parameter | Value |
|-----------|-------|
| Rotation Period | 100 seconds |
| Grace Period (dual-account) | 60 seconds |
| Vault Agent refresh | 30 seconds |
| VSO refreshAfter | 80 seconds (80% of rotation) |

## Deployment Toggle

All three delivery methods are deployed when `ldap_dual_account = true` in `deployments.tfdeploy.hcl`. The Vault Agent and CSI deployments use `count = var.ldap_dual_account ? 1 : 0` guards.

## Troubleshooting

### Check pod status
```bash
kubectl get pods -l app=ldap-credentials-app
kubectl get pods -l app=ldap-app-vault-agent
kubectl get pods -l app=ldap-app-csi
```

### View Vault Agent logs
```bash
kubectl logs -l app=ldap-app-vault-agent -c vault-agent
```

### Check CSI volume mount
```bash
kubectl exec -it $(kubectl get pod -l app=ldap-app-csi -o name) -- ls -la /vault/secrets/
```

### Verify Vault auth roles
```bash
vault read auth/kubernetes/role/vault-agent-app-role
vault read auth/kubernetes/role/csi-app-role
```

### Test LDAP static credentials
```bash
vault read ldap/static-cred/svc-single
vault read ldap/static-cred/svc-lib
```
