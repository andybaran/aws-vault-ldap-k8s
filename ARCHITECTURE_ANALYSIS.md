# AWS Vault LDAP Kubernetes Integration - Complete Architecture Analysis

## Overview
This is a Terraform stack that deploys an integrated LDAP (Active Directory) + Vault + Kubernetes environment on AWS. It supports both traditional single-account LDAP password rotation and a dual-account (blue/green) rotation model using a custom Vault plugin.

---

## 1. ROOT STACK ARCHITECTURE

### 1.1 Component Wiring (components.tfcomponent.hcl)

The stack consists of 5 main components orchestrated in a dependency chain:

```
kube0 (EKS Infrastructure)
  ↓
kube1 (K8s Tooling) ← kube0 outputs
  ↓
vault_cluster (Vault Deployment) ← kube1 outputs
  ↓
ldap (Active Directory DC) ← kube0 outputs
  ↓
vault_ldap_secrets (LDAP Secrets Engine) ← ldap outputs + vault_cluster outputs
  ↓
ldap_app (App Deployments) ← all above outputs
```

#### Component Dependencies & Data Flow:

**kube0 → kube1:**
- Outputs: `cluster_endpoint`, `kube_cluster_certificate_authority_data`, `demo_id`
- Used by: kube1 to configure Kubernetes provider

**kube0 → vault_cluster:**
- Outputs: `kube_cluster_certificate_authority_data`, `cluster_endpoint`
- Used by: providers.tfcomponent.hcl to configure helm and kubernetes providers

**kube1 → vault_cluster:**
- Outputs: `kube_namespace`
- Input: Vault will be deployed to this namespace

**kube0 → ldap:**
- Outputs: `vpc_id`, `first_public_subnet_id`, `shared_internal_sg_id`, `resources_prefix`
- Input: Network configuration for Domain Controller EC2 instance

**ldap → vault_ldap_secrets:**
- Output: `dc-priv-ip` (e.g., "10.0.1.50")
  - Used to construct LDAP URL: `ldaps://<dc-priv-ip>`
- Output: `password` (AD Administrator password)
  - Used for `ldap_bindpass` (binding to AD as Administrator)
- Output: `static_roles` (map of test user credentials)
  - Keys: "svc-rotate-a", "svc-rotate-b", "svc-rotate-c", "svc-rotate-d", "svc-rotate-e", "svc-rotate-f", "svc-single", "svc-lib"
  - Values: `{username, password, dn}`
  - Used to populate Vault static roles

**vault_cluster → vault_ldap_secrets:**
- Output: `vault_root_token` (used as provider token)
- Output: `vault_loadbalancer_hostname` (used as provider address)
- Output: `vso_vault_auth_name` (name of VaultAuth resource for VSO)

**vault_ldap_secrets → ldap_app:**
- Output: `ldap_secrets_mount_path` ("ldap")
- Output: `vault_app_auth_role_name` (K8s auth role for direct Vault polling in dual-account mode)
- Output: `static_role_names` (list of available roles)

### 1.2 Root Stack Variables (variables.tfcomponent.hcl)

| Variable | Type | Default | Purpose |
|----------|------|---------|---------|
| `customer_name` | string | - | Name for resource tagging |
| `region` | string | "us-east-2" | AWS region |
| `instance_type` | string | "t2.medium" | EC2 instance type for EKS nodes |
| `vault_image` | string | "hashicorp/vault-enterprise:1.21.2-ent" | Vault container image (overridden for dual-account) |
| `vault_license_key` | string | - | Vault Enterprise license |
| `ldap_app_image` | string | "ghcr.io/andybaran/vault-ldap-demo:latest" | Demo app image |
| `ldap_app_account_name` | string | "svc-rotate-a" | Default service account for single-account mode |
| `ldap_dual_account` | bool | false | Enable dual-account rotation with custom plugin |
| `grace_period` | number | 20 | Seconds both accounts are valid during rotation |
| `allowlist_ip` | string | "0.0.0.0/0" | IP CIDR for RDP/Kerberos access |
| `full_ui` | bool | false | Use full Windows GUI vs. Server Core for DC |
| `install_adds` | bool | true | Install AD Domain Services |
| `install_adcs` | bool | true | Install AD Certificate Services (enables LDAPS) |

### 1.3 Provider Configuration (providers.tfcomponent.hcl)

**Provider Versions:**
- aws: 6.27.0
- vault: 5.6.0
- kubernetes: 3.0.1
- helm: 3.1.1
- tls: ~4.0.5
- random: ~3.6.0
- http: ~3.5.0
- cloudinit: 2.3.7
- null: 3.2.4
- time: 0.13.1

**Provider Configuration Flow:**
```
AWS Provider: Uses ephemeral credentials from deployment stores
├─ Access Key ID
├─ Secret Access Key
└─ Session Token

Kubernetes Provider: Configured by kube0 outputs
├─ Host: cluster_endpoint
├─ CA Certificate: decoded kube_cluster_certificate_authority_data
└─ Token: eks_cluster_auth

Helm Provider: Uses same K8s config as Kubernetes provider

Vault Provider: Configured by vault_cluster outputs
├─ Address: vault_loadbalancer_hostname
├─ Token: vault_root_token
└─ Skip TLS Verify: true (development only)
```

### 1.4 Deployment Configuration (deployments.tfdeploy.hcl)

**Stack:** `development` in organization `andybaran`, project `ldap_stack`

**Key Settings:**
- Region: us-east-2
- Customer: fidelity
- EC2 Instance Type: c5.xlarge (for DC and EKS nodes)
- EKS AMI Release: 1.34.2-20260128
- Allowlist IP: 66.190.197.168/32 (for RDP access)
- Dual-Account Mode: true (uses custom plugin)
- Auto-approval: On successful plans

---

## 2. MODULES/AWS_DC/ - DOMAIN CONTROLLER MODULE

### 2.1 Purpose
Provisions a Windows Server 2025 EC2 instance configured as an Active Directory Domain Controller with test service accounts for LDAP integration testing.

### 2.2 Key Infrastructure Components

**EC2 Instance:**
- AMI: hc-base-windows-server-2025 (security-approved) or Windows_Server-2025-English-Full-Base (when full_ui=true)
- Instance Type: Variable (default: m7i-flex.xlarge)
- Root Volume: 128 GB gp2
- Security Groups: 
  - RDP ingress (port 3389, TCP/UDP) from allowlist_ip
  - Kerberos (port 88, TCP/UDP) from allowlist_ip
  - Shared internal SG for K8s communication
- IAM Profile: AmazonSSMManagedInstanceCore (for Systems Manager access)

**Elastic IP:**
- Provides stable public DNS and IP for remote access
- Output: `public-dns-address`, `eip-public-ip`

**TLS Keypair:**
- Generated locally to decrypt Windows Administrator password
- Output: `private-key` (private key in PEM format)

**Windows Initialization (User Data Script):**
- Domain promotion to "mydomain.local" (NetBIOS: "mydomain")
- AD DS installation and forest promotion
- AD CS (Certificate Authority) installation for LDAPS (port 636)
- Auto-creation of 8 test service accounts with random passwords

### 2.3 Test Service Accounts

Created in `CN=Users,DC=mydomain,DC=local` during DC initialization:

| Username | Password | Used By | Mode |
|----------|----------|---------|------|
| svc-rotate-a | Random | VSO deployment (primary) | Dual-account |
| svc-rotate-b | Random | Vault (standby) | Dual-account |
| svc-rotate-c | Random | Vault Agent (primary) | Dual-account |
| svc-rotate-d | Random | Vault Agent (standby) | Dual-account |
| svc-rotate-e | Random | CSI Driver (primary) | Dual-account |
| svc-rotate-f | Random | CSI Driver (standby) | Dual-account |
| svc-single | Random | Vault Agent (single account) | Single-account |
| svc-lib | Random | CSI Driver (single account) | Single-account |

**Password Generation:**
```hcl
resource "random_password" "test_user_password" {
  for_each = toset([...list...])
  length = 16
  override_special = "!@#"
  min_lower = 1, min_upper = 1, min_numeric = 1, min_special = 1
}
```

### 2.4 Outputs

| Output | Type | Description |
|--------|------|-------------|
| `dc-priv-ip` | string | Private IP (e.g., 10.0.1.50) - CRITICAL for LDAP URL construction |
| `public-dns-address` | string | Public DNS name via Elastic IP |
| `eip-public-ip` | string | Public IP address |
| `password` | string | Decrypted Administrator password |
| `private-key` | string | PEM-encoded RSA private key |
| `aws_keypair_name` | string | EC2 keypair name for RDP |
| `static_roles` | map | Test user credentials in format: `{username: string, password: string, dn: string}` |

**static_roles Output Format Example:**
```json
{
  "svc-rotate-a": {
    "username": "svc-rotate-a",
    "password": "Abc123!@#Xyz",
    "dn": "CN=svc-rotate-a,CN=Users,DC=mydomain,DC=local"
  },
  "svc-rotate-b": { ... },
  ...
}
```

### 2.5 Wait Duration
```
install_adds=false → 3m (plain Windows boot only)
install_adds=true, install_adcs=false → 7m (AD DS + reboot, no LDAPS)
install_adds=true, install_adcs=true → 10m (full setup with ADCS + NTDS restart)
```

### 2.6 LDAP Configuration Generated
- **LDAP URL:** `ldaps://<dc-priv-ip>` (port 636, encrypted via ADCS self-signed cert)
- **Bind DN:** `CN=Administrator,CN=Users,DC=mydomain,DC=local`
- **User Search Base:** `CN=Users,DC=mydomain,DC=local`
- **User Attribute:** `cn` (common name - required for AD schema)
- **Schema:** `ad` (Active Directory)

---

## 3. MODULES/VAULT_LDAP_SECRETS/ - LDAP SECRETS ENGINE CONFIGURATION

### 3.1 Architecture Overview

**Two Configuration Paths:**
1. **Single-Account Mode** (ldap_dual_account=false):
   - Uses standard Vault LDAP secrets engine
   - Simple password rotation (one account per role)
   - Single static password at any time

2. **Dual-Account Mode** (ldap_dual_account=true):
   - Uses custom Vault plugin: `vault-plugin-secrets-openldap`
   - Blue/green password rotation (two accounts per role)
   - Grace period overlap where both passwords are valid

### 3.2 Single-Account Mode (main.tf)

**LDAP Secrets Engine Setup:**

```hcl
resource "vault_ldap_secret_backend" "ad" {
  count = var.ldap_dual_account ? 0 : 1
  
  path = "ldap"  # Mount path
  
  # Connection
  url = "ldaps://<dc-priv-ip>"
  binddn = "CN=Administrator,CN=Users,DC=mydomain,DC=local"
  bindpass = "<Administrator password>"
  
  # Search configuration
  schema = "ad"
  userattr = "cn"  # Search by common name
  userdn = "CN=Users,DC=mydomain,DC=local"
  
  # TLS
  insecure_tls = true  # Self-signed cert from ADCS
  
  # Rotation
  skip_static_role_import_rotation = false
}
```

**Static Roles:**

```hcl
resource "vault_ldap_secret_backend_static_role" "roles" {
  for_each = var.ldap_dual_account ? {} : var.static_roles
  
  mount = vault_ldap_secret_backend.ad[0].path
  role_name = each.key  # e.g., "svc-rotate-a"
  username = each.value.username  # "svc-rotate-a"
  rotation_period = 100  # seconds
  skip_import_rotation = false
}
```

Each role manages a single AD account and rotates its password on the defined period.

**Policy:**
```hcl
path "ldap/static-cred/*" {
  capabilities = ["read"]
}
path "ldap/static-role/*" {
  capabilities = ["list"]
}
```

### 3.3 Dual-Account Mode (dual_account.tf)

**Custom Plugin Registration:**

```hcl
resource "vault_generic_endpoint" "register_plugin" {
  path = "sys/plugins/catalog/secret/ldap_dual_account"
  
  data_json = jsonencode({
    sha256  = "e71b4bec10963fe5f704d710f34be5a933330126799541fd1bd7b0e3536a8dad"
    command = "vault-plugin-secrets-openldap"
    version = "v0.17.0-dual-account.1"
  })
}
```

**Plugin Mount:**
```hcl
resource "vault_mount" "ldap_dual_account" {
  path = "ldap"
  type = "ldap_dual_account"
  description = "Dual-account LDAP secrets engine"
}
```

**Configuration:**
```hcl
resource "vault_generic_endpoint" "ldap_config" {
  path = "ldap/config"
  
  data_json = jsonencode({
    binddn       = "CN=Administrator,CN=Users,DC=mydomain,DC=local"
    bindpass     = "<Administrator password>"
    url          = "ldaps://<dc-priv-ip>"
    schema       = "ad"
    insecure_tls = true
    userattr     = "cn"
    userdn       = "CN=Users,DC=mydomain,DC=local"
  })
}
```

**Static Roles (3 types):**

1. **Primary Dual-Account Role (dual-rotation-demo):**
   ```json
   {
     "username": "svc-rotate-a",
     "dn": "CN=svc-rotate-a,CN=Users,DC=mydomain,DC=local",
     "username_b": "svc-rotate-b",
     "dn_b": "CN=svc-rotate-b,CN=Users,DC=mydomain,DC=local",
     "rotation_period": "100s",
     "dual_account_mode": true,
     "grace_period": "20s"
   }
   ```

2. **Vault Agent Dual Role (vault-agent-dual-role):**
   - Primary: svc-rotate-c / Secondary: svc-rotate-d

3. **CSI Dual Role (csi-dual-role):**
   - Primary: svc-rotate-e / Secondary: svc-rotate-f

4. **Single-Account Roles** (svc-single, svc-lib):
   - No dual_account_mode flag
   - Traditional single-password rotation

### 3.4 Dual-Account Rotation Flow

**States:**
1. **Active State**: Primary account (e.g., svc-rotate-a) is in use
   - Response fields: username, password, active_account="primary", rotation_state="active"
   - Standby fields absent

2. **Grace Period**: Both accounts valid for grace_period seconds
   - Response fields: All fields present including standby_username, standby_password
   - grace_period_end: timestamp when grace period ends
   - rotation_state="grace_period"

3. **Switchover**: Vault switches active_account to secondary
   - Next rotation cycle begins

**Password Update Fields in Secret Response:**
- `username` / `password` - Current active credentials
- `standby_username` / `standby_password` - Standby credentials (grace period only)
- `active_account` - "primary" or "secondary"
- `rotation_state` - "active" or "grace_period"
- `grace_period_end` - ISO timestamp of grace period end
- `last_vault_rotation` - Timestamp of last rotation
- `rotation_period` - Rotation interval in seconds
- `ttl` - Time-to-live of this credential state
- `dual_account_mode` - boolean indicator

### 3.5 Kubernetes Authentication Backend (kubernetes_auth.tf)

**Backend Setup:**
```hcl
resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "config" {
  backend = "kubernetes"
  kubernetes_host = "https://<cluster-endpoint>"
  kubernetes_ca_cert = <base64-decoded CA>
  disable_local_ca_jwt = false  # Validate locally, not via API
}
```

**VSO Role (always created):**
```hcl
role_name = "vso-role"
bound_service_account_names = ["vso-auth"]
bound_service_account_namespaces = [var.kube_namespace]
token_ttl = 600
token_policies = ["ldap-static-read"]
```

**Dual-Account Mode Roles (only when ldap_dual_account=true):**

1. **ldap-app-role**: For app direct Vault polling
   - SA: ldap-app-vault-auth

2. **vault-agent-app-role**: For Vault Agent sidecar
   - SA: ldap-app-vault-agent

3. **csi-app-role**: For CSI Driver
   - SA: ldap-app-csi

### 3.6 Outputs

| Output | Value | Used By |
|--------|-------|---------|
| `ldap_secrets_mount_path` | "ldap" | All apps for mount point |
| `ldap_secrets_mount_accessor` | mount accessor | Internal reference |
| `static_role_names` | Map of role names | Service discovery |
| `static_role_policy_name` | "ldap-static-read" | Auth role policy binding |
| `vault_app_auth_role_name` | "ldap-app-role" | LDAP app for direct polling |

### 3.7 Variable Inputs

| Variable | Type | Default | Purpose |
|----------|------|---------|---------|
| `ldap_url` | string | - | CRITICAL: "ldaps://<dc-priv-ip>" from DC module |
| `ldap_binddn` | string | "CN=Administrator,CN=Users,DC=mydomain,DC=local" | Vault's service account DN |
| `ldap_bindpass` | string (sensitive) | - | CRITICAL: Administrator password from DC module |
| `ldap_userdn` | string | "CN=Users,DC=mydomain,DC=local" | Search base for users |
| `secrets_mount_path` | string | "ldap" | Where engine is mounted |
| `static_roles` | map(object) | - | CRITICAL: Test user map from DC module |
| `kubernetes_host` | string | - | K8s API URL for auth backend |
| `kubernetes_ca_cert` | string | - | K8s CA cert (base64) for JWT validation |
| `kube_namespace` | string | - | K8s namespace for VSO |
| `ldap_dual_account` | bool | false | Enable dual-account plugin |
| `grace_period` | number | 15 | Overlap time in seconds |
| `plugin_sha256` | string | "e71b4bec10963fe5f704d710f34be5a933330126799541fd1bd7b0e3536a8dad" | Custom plugin binary hash |

---

## 4. MODULES/LDAP_APP/ - APPLICATION DEPLOYMENTS

### 4.1 Overview
Deploys 1-3 instances of the LDAP credentials demo app, each demonstrating a different secret delivery method:
1. VSO (Vault Secrets Operator) - via VaultDynamicSecret CRD
2. Vault Agent Sidecar - via init container + sidecar
3. CSI Driver - via Secrets Store CSI Driver

Each uses different AD service accounts and Kubernetes auth roles.

### 4.2 VSO Deployment (ldap_app.tf)

**VaultDynamicSecret CR:**
```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultDynamicSecret
metadata:
  name: ldap-credentials-app
  namespace: vso
spec:
  mount: ldap  # Vault LDAP mount point
  path: static-cred/demo-service-account  # Or other role name
  destination:
    name: ldap-credentials  # K8s secret name
    create: true
  allowStaticCreds: true  # Allow rotation without lease
  refreshAfter: "80s"  # 80% of rotation period
  vaultAuthRef: default  # VaultAuth resource name
  rolloutRestartTargets:
    - kind: Deployment
      name: ldap-credentials-app
```

**Service Account (dual-account only):**
- Name: ldap-app-vault-auth
- Token audience: "vault" (for direct Vault API calls)

**Deployment:**
- Replicas: 2
- Strategy: RollingUpdate (max 1 unavailable, max 1 surge)

**Container Environment Variables:**

Static (from VSO secret):
```
LDAP_USERNAME=<username>
LDAP_PASSWORD=<password>
LDAP_LAST_VAULT_PASSWORD=<last_vault_rotation>
ROTATION_PERIOD=<rotation_period>
ROTATION_TTL=<ttl>
SECRET_DELIVERY_METHOD=vault-secrets-operator
```

Dual-account (when enabled):
```
DUAL_ACCOUNT_MODE=true
ACTIVE_ACCOUNT=<primary|secondary>
ROTATION_STATE=<active|grace_period>
STANDBY_USERNAME=<username_b> (optional, grace_period only)
STANDBY_PASSWORD=<password_b> (optional, grace_period only)
GRACE_PERIOD_END=<timestamp> (optional, grace_period only)
GRACE_PERIOD=20
VAULT_ADDR=http://vault.vso.svc.cluster.local:8200
VAULT_AUTH_ROLE=ldap-app-role
LDAP_MOUNT_PATH=ldap
LDAP_STATIC_ROLE_NAME=demo-rotation-demo
```

**Service:**
- Type: LoadBalancer
- Port: 80 → 8080 (container port)

### 4.3 Vault Agent Sidecar Deployment (vault_agent_app.tf)

**Only created when ldap_dual_account=true**

**Service Account:**
- Name: ldap-app-vault-agent
- Automount: true
- Token audience: "vault"

**ConfigMap: vault-agent-config**
Two configs:
1. `vault-agent-init-config.hcl` - Init container (exit_after_auth=true)
2. `vault-agent-config.hcl` - Sidecar (exit_after_auth=false, refresh every 30s)

Both render credentials to `/vault/secrets/ldap-creds` file:
```
LDAP_USERNAME=<username>
LDAP_PASSWORD=<password>
LDAP_LAST_VAULT_PASSWORD=<last_vault_rotation>
ROTATION_PERIOD=<rotation_period>
ROTATION_TTL=<ttl>
ACTIVE_ACCOUNT=<primary|secondary>
ROTATION_STATE=<active|grace_period>
DUAL_ACCOUNT_MODE=<true|false>
[Optional during grace_period]:
STANDBY_USERNAME=<username_b>
STANDBY_PASSWORD=<password_b>
GRACE_PERIOD_END=<timestamp>
```

**Pod Structure:**
```
Init Container: vault-agent-init
├─ Image: hashicorp/vault:1.18.0
├─ Command: agent -config=/vault/config/vault-agent-init-config.hcl
├─ Mounts: vault-secrets, vault-agent-config, vault-token
└─ Resources: 50m CPU / 64Mi memory

Sidecar Container: vault-agent
├─ Image: hashicorp/vault:1.18.0
├─ Command: agent -config=/vault/config/vault-agent-config.hcl
├─ Continuous refresh with static_secret_render_interval=30s
└─ Resources: 50m CPU / 64Mi memory

App Container: ldap-app
├─ Image: ghcr.io/andybaran/vault-ldap-demo:latest
├─ Environment: SECRETS_FILE_PATH=/vault/secrets/ldap-creds
├─ Mounts: vault-secrets (read-only), vault-token (read-only)
├─ Reads credentials from file, not K8s secret
└─ Resources: 100m CPU / 128Mi memory
```

**Environment Variables:**
```
SECRET_DELIVERY_METHOD=vault-agent-sidecar
SECRETS_FILE_PATH=/vault/secrets/ldap-creds
DUAL_ACCOUNT_MODE=true
VAULT_ADDR=http://vault.vso.svc.cluster.local:8200
VAULT_AUTH_ROLE=vault-agent-app-role
LDAP_MOUNT_PATH=ldap
LDAP_STATIC_ROLE_NAME=vault-agent-dual-role
GRACE_PERIOD=20
ROTATION_PERIOD=100
```

**Service:**
- Type: LoadBalancer
- Port: 80 → 8080

### 4.4 CSI Driver Deployment (csi_app.tf)

**Only created when ldap_dual_account=true**

**Service Account:**
- Name: ldap-app-csi
- Automount: true

**SecretProviderClass:**
```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: ldap-csi-credentials
spec:
  provider: vault
  parameters:
    roleName: csi-app-role
    vaultAddress: http://vault.vso.svc.cluster.local:8200
    audience: vault
    objects:
      - objectName: username
        secretPath: ldap/static-cred/csi-dual-role
        secretKey: username
      - objectName: password
        secretPath: ldap/static-cred/csi-dual-role
        secretKey: password
      - objectName: rotation_state
        secretPath: ldap/static-cred/csi-dual-role
        secretKey: rotation_state
      - objectName: active_account
        secretPath: ldap/static-cred/csi-dual-role
        secretKey: active_account
      - objectName: ttl
        secretPath: ldap/static-cred/csi-dual-role
        secretKey: ttl
      - objectName: rotation_period
        secretPath: ldap/static-cred/csi-dual-role
        secretKey: rotation_period
      - objectName: last_vault_rotation
        secretPath: ldap/static-cred/csi-dual-role
        secretKey: last_vault_rotation
      - objectName: ldap-creds.json
        secretPath: ldap/static-cred/csi-dual-role  # Entire response as JSON
```

**Pod Structure:**
```
App Container: ldap-app
├─ Image: ghcr.io/andybaran/vault-ldap-demo:latest
├─ CSI Volume Mounts: /vault/secrets (read-only)
├─ Token Mount: /var/run/secrets/vault (read-only)
├─ Files in /vault/secrets/:
│  ├─ username (text)
│  ├─ password (text)
│  ├─ rotation_state (text)
│  ├─ active_account (text)
│  ├─ rotation_period (text)
│  ├─ last_vault_rotation (text)
│  ├─ ttl (text)
│  └─ ldap-creds.json (full response as JSON)
└─ Resources: 100m CPU / 128Mi memory
```

**Environment Variables:**
```
SECRET_DELIVERY_METHOD=vault-csi-driver
SECRETS_FILE_PATH=/vault/secrets
DUAL_ACCOUNT_MODE=true
VAULT_ADDR=http://vault.vso.svc.cluster.local:8200
VAULT_AUTH_ROLE=csi-app-role
LDAP_MOUNT_PATH=ldap
LDAP_STATIC_ROLE_NAME=csi-dual-role
GRACE_PERIOD=20
ROTATION_PERIOD=100
```

**Service:**
- Type: LoadBalancer
- Port: 80 → 8080

### 4.5 Module Variables

| Variable | Type | Default | Purpose |
|----------|------|---------|---------|
| `kube_namespace` | string | "default" | K8s namespace |
| `ldap_mount_path` | string | "ldap" | Vault LDAP mount |
| `ldap_static_role_name` | string | "demo-service-account" | Role to use (VSO only) |
| `vso_vault_auth_name` | string | "default" | VaultAuth resource name |
| `static_role_rotation_period` | number | 30 | Rotation period in seconds |
| `ldap_app_image` | string | "ghcr.io/andybaran/vault-ldap-demo:latest" | App container image |
| `ldap_dual_account` | bool | false | Enable dual-account deployments |
| `grace_period` | number | 15 | Grace period in seconds |
| `vault_app_auth_role` | string | "" | K8s auth role for app polling |
| `vault_agent_image` | string | "hashicorp/vault:1.18.0" | Vault Agent image |

### 4.6 Outputs

| Output | Value | Description |
|--------|-------|-------------|
| `ldap_app_service_name` | "ldap-credentials-app" | VSO deployment service |
| `ldap_app_url` | "http://<LB-hostname>" | VSO app access URL |
| `ldap_app_vault_agent_url` | "http://<LB-hostname>" | Vault Agent app access URL (dual-account only) |
| `ldap_app_csi_url` | "http://<LB-hostname>" | CSI app access URL (dual-account only) |

---

## 5. MODULES/VAULT/ - VAULT DEPLOYMENT

### 5.1 Vault Cluster Helm Deployment (vault.tf)

**Helm Chart:**
- Repository: https://helm.releases.hashicorp.com
- Chart: vault
- Version: 0.31.0
- Namespace: var.kube_namespace

**Core Configuration:**

When `ldap_dual_account=true`, adds custom values:
```yaml
server:
  ha:
    raft:
      config: |
        ui = true
        listener "tcp" {
          tls_disable = 1
          address = "[::]:8200"
          cluster_address = "[::]:8201"
        }
        storage "raft" {
          path = "/vault/data"
        }
        service_registration "kubernetes" {}
        plugin_directory = "/vault/plugins"
```

The `plugin_directory = "/vault/plugins"` is CRITICAL for custom plugin loading.

**Helm Values (via set blocks):**

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `global.tlsDisable` | true | Development environment (no TLS) |
| `server.ha.enabled` | true | High availability |
| `server.ha.raft.enabled` | true | Raft storage backend |
| `server.ha.raft.setNodeId` | true | Auto-set node IDs |
| `server.image.repository` | Split from vault_image | Container repository |
| `server.image.tag` | Split from vault_image | Container tag |
| `server.enterpriseLicense.secretName` | vault-license | K8s secret for license |
| `server.enterpriseLicense.secretKey` | license | Key in secret |
| `ui.enabled` | true | Enable Vault UI |
| `server.dataStorage.enabled` | true | Persistent data |
| `server.dataStorage.size` | 10Gi | Data volume size |
| `server.dataStorage.storageClass` | vault-storage | Custom storage class |
| `server.auditStorage.enabled` | true | Audit logging |
| `server.auditStorage.size` | 10Gi | Audit volume size |
| `injector.enabled` | true | Vault injector for pods |
| `csi.enabled` | true | Secrets Store CSI driver support |
| `server.service.type` | LoadBalancer | Expose via LB |
| `server.service.annotations` | NLB config | AWS NLB configuration |
| `ui.serviceType` | LoadBalancer | UI exposed via LB |

**Vault Image Selection:**
```hcl
locals {
  vault_image_parts = split(":", var.vault_image)
  vault_repository = local.vault_image_parts[0]
  vault_tag = length(local.vault_image_parts) > 1 ? local.vault_image_parts[1] : "latest"
}
```

When `ldap_dual_account=true`, image is: `ghcr.io/andybaran/vault-with-openldap-plugin:dual-account-rotation`

### 5.2 Storage Configuration (storage.tf)

**Storage Class:**
```hcl
resource "kubernetes_storage_class_v1" "vault_storage" {
  metadata {
    name = "vault-storage"
  }
  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy = "Delete"
  # Allows volume expansion
  allow_volume_expansion = true
  parameters = {
    type      = "gp3"
    iops      = "3000"
    throughput = "125"
  }
}
```

**Persistent Volumes:**
- Data Storage: 10Gi (Vault's encrypted data)
- Audit Storage: 10Gi (Audit logs)
- Both use EBS gp3 volumes

### 5.3 Vault Initialization (vault_init.tf)

**Kubernetes Job: vault-init**
Runs in pod with access to Vault cluster to:

1. **Check Initialization Status**
   - `vault status` to determine if already initialized

2. **Initialize Vault** (if needed)
   - `vault operator init -key-shares=5 -key-threshold=3`
   - Stores init data (keys, root token) in K8s secret "vault-init-data"

3. **Unseal Vault**
   - Uses 3 of 5 unseal keys to unseal all 3 cluster nodes
   - `vault operator unseal <key1> <key2> <key3>`

4. **Setup Raft Cluster**
   - Joins vault-1 and vault-2 to vault-0's Raft cluster
   - `vault operator raft join http://vault-0.vault-internal:8200`

**Data Stored:**
```json
{
  "unseal_keys_b64": ["key1...", "key2...", ...],
  "root_token": "hvs.xxxxx"
}
```

**Service Account:**
- Name: secret-writer-sa
- Permissions: Get/Create/Patch vault-init-data secret

### 5.4 VSO Integration (vso.tf)

Creates VaultAuth resource for Vault Secrets Operator:
```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: default
  namespace: vso
spec:
  method: kubernetes
  mount: kubernetes  # Auth method mount
  kubernetes:
    role: vso-role   # K8s auth role from vault_ldap_secrets module
    serviceAccount: vso-auth
```

### 5.5 CSI Driver Integration (csi_driver.tf)

**VaultConnection Resource:**
```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: default
spec:
  address: http://vault:8200
  skipTLSVerify: true
```

**VaultAuth Resource (for CSI):**
Similar to VSO, but may use different K8s auth role.

### 5.6 Module Variables

| Variable | Type | Default | Purpose |
|----------|------|---------|---------|
| `kube_namespace` | string | - | K8s namespace for Vault |
| `vault_image` | string | "hashicorp/vault-enterprise:1.21.2-ent" | Vault container image |
| `ldap_dual_account` | bool | false | Enable plugin_directory in config |

### 5.7 Outputs

| Output | Value | Used By |
|--------|-------|---------|
| `vault_unseal_keys` | List of base64 keys | Backup/disaster recovery |
| `vault_root_token` | Root token | Provider configuration |
| `vault_namespace` | K8s namespace | Reference |
| `vault_service_name` | "vault" | DNS name: vault.ns.svc.cluster.local |
| `vault_loadbalancer_hostname` | "http://<LB>:8200" | Provider address for Vault provider |
| `vault_ui_loadbalancer_hostname` | "http://<LB>:8200" | UI access |
| `vso_vault_auth_name` | "default" | VaultAuth resource name for VSO |

---

## 6. DATA FLOW DIAGRAM

```
┌─────────────────────────────────────────────────────────────────────┐
│                    AWS Vault LDAP K8s Stack                        │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ AWS_DC Module (Windows Server 2025)                                │
│ ├─ Active Directory Domain Controller                              │
│ │  └─ Domain: mydomain.local                                      │
│ ├─ Test Service Accounts (8):                                     │
│ │  ├─ svc-rotate-a (password: Xyz123!@#)                         │
│ │  ├─ svc-rotate-b (password: Abc456!@#)                         │
│ │  └─ ... 6 more accounts                                         │
│ └─ Outputs: dc-priv-ip, password, static_roles                   │
│            └─ Feeds into: vault_ldap_secrets                      │
└─────────────────────────────────────────────────────────────────────┘
         ↓ (dc-priv-ip, bindpass, static_roles)

┌─────────────────────────────────────────────────────────────────────┐
│ vault_ldap_secrets Module                                           │
│ ├─ LDAP Secrets Engine Setup                                       │
│ │  ├─ URL: ldaps://10.0.1.50:636                                  │
│ │  ├─ Bind DN: CN=Administrator,CN=Users,DC=mydomain,DC=local   │
│ │  ├─ Bind Password: <from DC>                                   │
│ │  └─ User Search Base: CN=Users,DC=mydomain,DC=local           │
│ │                                                                 │
│ ├─ Single-Account Mode (ldap_dual_account=false):               │
│ │  └─ Static Roles: svc-rotate-a (rotation: 100s)               │
│ │     └─ Single password per account                             │
│ │                                                                 │
│ ├─ Dual-Account Mode (ldap_dual_account=true):                  │
│ │  ├─ Custom Plugin: vault-plugin-secrets-openldap              │
│ │  └─ Dual Roles:                                               │
│ │     ├─ dual-rotation-demo (svc-rotate-a ↔ svc-rotate-b)      │
│ │     ├─ vault-agent-dual-role (svc-rotate-c ↔ svc-rotate-d)  │
│ │     └─ csi-dual-role (svc-rotate-e ↔ svc-rotate-f)          │
│ │                                                                │
│ └─ Kubernetes Auth Backend (kubernetes)                         │
│    ├─ VSO Role: vso-role (SA: vso-auth)                        │
│    ├─ LDAP App Role: ldap-app-role (SA: ldap-app-vault-auth)  │
│    ├─ Vault Agent Role: vault-agent-app-role (SA: ldap-app-vault-agent)
│    └─ CSI Role: csi-app-role (SA: ldap-app-csi)               │
│                                                                 │
│ Outputs: ldap_secrets_mount_path, vault_app_auth_role_name    │
│         └─ Feeds into: ldap_app                                │
└─────────────────────────────────────────────────────────────────────┘
         ↓ (mount_path, role_names)

┌─────────────────────────────────────────────────────────────────────┐
│ ldap_app Module (Kubernetes Deployments)                            │
│                                                                     │
│ ┌─────────────────────────────────────────────────────────────┐  │
│ │ VSO Deployment (Always)                                    │  │
│ │ ├─ Service Account: vso (or none, uses VSO's vso-auth)    │  │
│ │ ├─ Deployment: ldap-credentials-app (replicas: 2)         │  │
│ │ ├─ VaultDynamicSecret CR:                                 │  │
│ │ │  ├─ Mount: ldap                                         │  │
│ │ │  ├─ Path: static-cred/demo-service-account              │  │
│ │ │  ├─ Destination: ldap-credentials (K8s secret)          │  │
│ │ │  └─ Refresh: Every 80s                                  │  │
│ │ ├─ Container Environment:                                 │  │
│ │ │  ├─ LDAP_USERNAME (from K8s secret)                    │  │
│ │ │  ├─ LDAP_PASSWORD (from K8s secret)                    │  │
│ │ │  └─ SECRET_DELIVERY_METHOD=vault-secrets-operator      │  │
│ │ └─ Service: LoadBalancer (80→8080)                        │  │
│ └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
│ ┌─────────────────────────────────────────────────────────────┐  │
│ │ Vault Agent Sidecar (dual_account=true only)              │  │
│ │ ├─ Service Account: ldap-app-vault-agent                  │  │
│ │ ├─ Init Container: vault-agent-init (render credentials)  │  │
│ │ │  └─ Output: /vault/secrets/ldap-creds (env file)       │  │
│ │ ├─ Sidecar Container: vault-agent (continuous refresh)   │  │
│ │ ├─ App Container: ldap-app                                │  │
│ │ │  └─ Reads: /vault/secrets/ldap-creds                   │  │
│ │ │  └─ Env: SECRET_DELIVERY_METHOD=vault-agent-sidecar   │  │
│ │ └─ Service: LoadBalancer (80→8080)                        │  │
│ └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
│ ┌─────────────────────────────────────────────────────────────┐  │
│ │ CSI Driver Deployment (dual_account=true only)            │  │
│ │ ├─ Service Account: ldap-app-csi                          │  │
│ │ ├─ SecretProviderClass: ldap-csi-credentials             │  │
│ │ │  └─ Role: csi-app-role                                 │  │
│ │ │  └─ Vault Address: http://vault:8200                   │  │
│ │ │  └─ Objects: username, password, rotation_state, etc.  │  │
│ │ ├─ CSI Volume Mount: /vault/secrets (read-only)          │  │
│ │ ├─ App Container: ldap-app                                │  │
│ │ │  └─ Reads: /vault/secrets/* (individual files)         │  │
│ │ │  └─ Env: SECRET_DELIVERY_METHOD=vault-csi-driver      │  │
│ │ └─ Service: LoadBalancer (80→8080)                        │  │
│ └─────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 7. CRITICAL WIRING POINTS

### 7.1 DC → vault_ldap_secrets
```hcl
ldap_url = "ldaps://${component.ldap.dc-priv-ip}"              # CRITICAL
ldap_bindpass = component.ldap.password                         # CRITICAL
static_roles = component.ldap.static_roles                      # CRITICAL
```

**Failure Modes:**
- Missing dc-priv-ip → LDAP connection fails
- Wrong bindpass → Authentication fails
- Empty static_roles → No roles to rotate

### 7.2 vault_cluster → vault_ldap_secrets
```hcl
kubernetes_host = component.kube0.cluster_endpoint
kubernetes_ca_cert = component.kube0.kube_cluster_certificate_authority_data
kube_namespace = component.kube1.kube_namespace
```

**Failure Modes:**
- Wrong K8s endpoint → Auth backend misconfigured
- Mismatched CA cert → JWT validation fails
- Wrong namespace → Apps can't authenticate

### 7.3 vault_ldap_secrets → ldap_app
```hcl
ldap_mount_path = component.vault_ldap_secrets.ldap_secrets_mount_path
ldap_static_role_name = var.ldap_dual_account ? "dual-rotation-demo" : var.ldap_app_account_name
vault_app_auth_role = component.vault_ldap_secrets.vault_app_auth_role_name
```

**Failure Modes:**
- Wrong mount path → Apps can't read secrets
- Role doesn't exist → Permission denied
- Missing auth role → Direct Vault polling fails (dual-account mode)

### 7.4 vault_image Selection
```hcl
vault_image = var.ldap_dual_account ? 
              "ghcr.io/andybaran/vault-with-openldap-plugin:dual-account-rotation" : 
              var.vault_image
```

**Failure Modes:**
- Wrong image for dual-account → Plugin not available in /vault/plugins
- Missing plugin binary → Mount fails with unknown type error

---

## 8. ENVIRONMENT VARIABLE MAPPING BY DEPLOYMENT METHOD

### 8.1 VSO Deployment Environment

**From K8s Secret (injected by VSO):**
```
LDAP_USERNAME                  ← secret.data.username
LDAP_PASSWORD                  ← secret.data.password
LDAP_LAST_VAULT_PASSWORD       ← secret.data.last_vault_rotation
ROTATION_PERIOD                ← secret.data.rotation_period
ROTATION_TTL                   ← secret.data.ttl
ACTIVE_ACCOUNT                 ← secret.data.active_account (dual-account)
ROTATION_STATE                 ← secret.data.rotation_state (dual-account)
STANDBY_USERNAME               ← secret.data.standby_username (optional, grace_period)
STANDBY_PASSWORD               ← secret.data.standby_password (optional, grace_period)
GRACE_PERIOD_END               ← secret.data.grace_period_end (optional, grace_period)
```

**Hardcoded:**
```
SECRET_DELIVERY_METHOD=vault-secrets-operator
DUAL_ACCOUNT_MODE=true (when ldap_dual_account=true)
GRACE_PERIOD=20
VAULT_ADDR=http://vault.vso.svc.cluster.local:8200 (for polling)
VAULT_AUTH_ROLE=ldap-app-role (for direct polling)
LDAP_MOUNT_PATH=ldap
LDAP_STATIC_ROLE_NAME=demo-rotation-demo
```

### 8.2 Vault Agent Sidecar Environment

**From File (rendered by Vault Agent to /vault/secrets/ldap-creds):**
```
LDAP_USERNAME                  ← File parsing: LDAP_USERNAME=...
LDAP_PASSWORD                  ← File parsing: LDAP_PASSWORD=...
LDAP_LAST_VAULT_PASSWORD       ← File parsing: LDAP_LAST_VAULT_PASSWORD=...
ROTATION_PERIOD                ← File parsing: ROTATION_PERIOD=...
ROTATION_TTL                   ← File parsing: ROTATION_TTL=...
ACTIVE_ACCOUNT                 ← File parsing: ACTIVE_ACCOUNT=...
ROTATION_STATE                 ← File parsing: ROTATION_STATE=...
STANDBY_USERNAME               ← File parsing: STANDBY_USERNAME=... (optional)
STANDBY_PASSWORD               ← File parsing: STANDBY_PASSWORD=... (optional)
GRACE_PERIOD_END               ← File parsing: GRACE_PERIOD_END=... (optional)
```

**Hardcoded:**
```
SECRET_DELIVERY_METHOD=vault-agent-sidecar
SECRETS_FILE_PATH=/vault/secrets/ldap-creds
DUAL_ACCOUNT_MODE=true
VAULT_ADDR=http://vault.vso.svc.cluster.local:8200
VAULT_AUTH_ROLE=vault-agent-app-role
LDAP_MOUNT_PATH=ldap
LDAP_STATIC_ROLE_NAME=vault-agent-dual-role
GRACE_PERIOD=20
ROTATION_PERIOD=100
```

### 8.3 CSI Driver Environment

**From Files (mounted via CSI at /vault/secrets):**
```
LDAP_USERNAME                  ← File content: /vault/secrets/username
LDAP_PASSWORD                  ← File content: /vault/secrets/password
ROTATION_PERIOD                ← File content: /vault/secrets/rotation_period
ROTATION_TTL                   ← File content: /vault/secrets/ttl
ROTATION_STATE                 ← File content: /vault/secrets/rotation_state
ACTIVE_ACCOUNT                 ← File content: /vault/secrets/active_account
LAST_VAULT_ROTATION            ← File content: /vault/secrets/last_vault_rotation
[Full JSON Response]           ← File content: /vault/secrets/ldap-creds.json
```

**Hardcoded:**
```
SECRET_DELIVERY_METHOD=vault-csi-driver
SECRETS_FILE_PATH=/vault/secrets
DUAL_ACCOUNT_MODE=true
VAULT_ADDR=http://vault.vso.svc.cluster.local:8200
VAULT_AUTH_ROLE=csi-app-role
LDAP_MOUNT_PATH=ldap
LDAP_STATIC_ROLE_NAME=csi-dual-role
GRACE_PERIOD=20
ROTATION_PERIOD=100
```

---

## 9. KEY ARCHITECTURAL DECISIONS

### 9.1 LDAP URL Format
- **Single-Account & Dual-Account:** Always `ldaps://<dc-priv-ip>`
- **Port:** 636 (LDAPS, encrypted)
- **Prerequisite:** ADCS must be installed (install_adcs=true)
- **Certificate:** Self-signed from AD CS (insecure_tls=true in config)

### 9.2 User Search Attribute
- **Attribute:** `cn` (common name)
- **Not:** `userPrincipalName` (AD default)
- **Reason:** Vault searches with bare username (e.g., "svc-rotate-a"), not full UPN
- **AD Default:** Would require "svc-rotate-a@mydomain.local"

### 9.3 Static Role Import Rotation
- **skip_static_role_import_rotation=false**
- **Effect:** On role creation, Vault rotates the password once
- **Reason:** Ensures last_vault_rotation timestamp is valid for VSO metadata

### 9.4 Grace Period Mechanism (Dual-Account)
- **Duration:** Configurable (default: 20 seconds)
- **State:** Both accounts valid during rotation transition
- **Credentials in Response:**
  - **Active:** Primary account details
  - **Standby:** Secondary account details (only during grace_period)
- **Use Case:** Allows clients to switch authentication without interruption

### 9.5 Plugin Behavior vs Standard LDAP
| Aspect | Single-Account | Dual-Account |
|--------|---|---|
| Accounts per Role | 1 | 2 (primary & secondary) |
| Response Fields | username, password | username, password, standby_username, standby_password, active_account, rotation_state, grace_period_end |
| Rotation Model | Simple override | Blue/green with grace period |
| Plugin Type | Native Vault | Custom vault-plugin-secrets-openldap |
| Mount Type | "ldap" | "ldap_dual_account" |

---

## 10. DEPLOYMENT SEQUENCE & DEPENDENCIES

1. **kube0** - Create EKS cluster, networking, security groups
2. **kube1** - Deploy K8s tools (depends on kube0 outputs)
3. **vault_cluster** - Deploy Vault via Helm (depends on kube1 namespace)
4. **ldap** - Launch Windows DC in parallel (depends on kube0 network)
5. **vault_ldap_secrets** - Configure LDAP engine (depends on ldap outputs + vault_cluster ready)
6. **ldap_app** - Deploy apps (depends on all above)

**Critical Wait Points:**
- DC needs 10 minutes (with ADCS) for AD promotion + user creation
- Vault initialization job waits for pod readiness (~2 min)
- VSO must have CRD installed before VaultDynamicSecret creation

---

## 11. TROUBLESHOOTING GUIDE

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| LDAP connection fails | dc-priv-ip not routable from K8s | Check security group: shared_internal_sg_id |
| Authentication fails | Wrong bindpass | Verify Administrator password from DC |
| Role creation fails | static_roles empty | Wait for DC initialization (10 min) |
| Dual-account plugin fails | Custom image not loaded | Ensure ldap_dual_account=true and correct vault_image |
| VSO can't read secret | Vault auth fails | Check vso-role in Kubernetes auth backend |
| CSI mounts empty | SecretProviderClass misconfigured | Verify role name matches backend config |
| Grace period not visible | rotation_state not in response | Enable dual_account_mode in role config |

---

## SUMMARY TABLE: All Inputs/Outputs

### Components → Modules
```
kube0 outputs:
├─ cluster_endpoint → vault_cluster, vault_ldap_secrets, kube1
├─ vpc_id, first_public_subnet_id, shared_internal_sg_id → ldap
├─ kube_cluster_certificate_authority_data → vault_ldap_secrets, providers
└─ eks_cluster_auth → providers (kubernetes/helm)

kube1 outputs:
├─ kube_namespace → vault_cluster, vault_ldap_secrets, ldap_app, vault
└─ vso_vault_auth_name → ldap_app

vault_cluster outputs:
├─ vault_root_token → providers (vault), vault_ldap_secrets
├─ vault_loadbalancer_hostname → providers (vault)
├─ vso_vault_auth_name → ldap_app
└─ [K8s services created] → K8s auth backend

ldap outputs:
├─ dc-priv-ip → vault_ldap_secrets (CRITICAL: LDAP URL)
├─ password → vault_ldap_secrets (CRITICAL: bindpass)
└─ static_roles → vault_ldap_secrets (CRITICAL: role definitions)

vault_ldap_secrets outputs:
├─ ldap_secrets_mount_path → ldap_app
├─ vault_app_auth_role_name → ldap_app (dual-account)
└─ [K8s auth roles created] → Service accounts
```

