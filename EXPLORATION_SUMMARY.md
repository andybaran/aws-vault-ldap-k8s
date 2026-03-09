# AWS Vault LDAP Kubernetes Integration - Exploration Summary

## Executive Summary

This codebase implements a complete LDAP + Vault + Kubernetes integration stack on AWS, supporting both:
1. **Single-Account Mode**: Traditional password rotation (1 account per role)
2. **Dual-Account Mode**: Blue/green rotation with grace periods (2 accounts per role)

The architecture is highly modular and demonstrates three different Kubernetes secret delivery methods:
- **Vault Secrets Operator (VSO)**: K8s CRD syncs secrets to K8s Secret objects
- **Vault Agent Sidecar**: Init container + sidecar renders credentials to files
- **CSI Driver**: Secrets Store CSI Driver mounts secrets as ephemeral volumes

---

## Documentation Created

### 1. **ARCHITECTURE_ANALYSIS.md** (1221 lines)
Complete technical reference covering:
- Root stack architecture and component wiring
- All inputs/outputs and variable mappings
- Detailed module-by-module breakdown
- Data flow diagrams
- LDAP configuration details
- Dual-account rotation mechanisms
- Kubernetes authentication backend setup
- Environment variable mapping
- Troubleshooting guide

**Use this for:** Understanding the complete system, debugging integration issues, reference documentation

### 2. **QUICK_REFERENCE.md** (430+ lines)
Fast lookup guide with:
- Critical inputs/outputs flow
- Key variables by component
- Environment variables by deployment method
- Kubernetes auth roles reference
- Vault plugin configuration
- Single vs dual-account comparison table
- Dependency chain visualization
- LDAP configuration summary

**Use this for:** Quick lookups, variable reference, comparison between modes

### 3. **EXPLORATION_SUMMARY.md** (this file)
High-level overview and index

---

## Key Findings

### 1. Root Stack Structure
```
5 Components in Dependency Order:
├─ kube0       (EKS infrastructure)
├─ kube1       (K8s namespace & tooling)
├─ vault_cluster (Vault HA via Helm)
├─ ldap        (AD Domain Controller)
└─ vault_ldap_secrets (LDAP engine config)
                ↓
        ldap_app (3 deployment methods)
```

### 2. Critical Data Flow
The DC module outputs three critical values consumed by vault_ldap_secrets:

```hcl
ldap_url = "ldaps://${component.ldap.dc-priv-ip}"
ldap_bindpass = component.ldap.password
static_roles = component.ldap.static_roles
```

For OpenLDAP replacement: These outputs must be maintained in the same format.

### 3. Test Service Accounts
8 accounts created on DC, used for different purposes:

| Account | Primary Use | Pair | Mode |
|---------|------------|------|------|
| svc-rotate-a | VSO/Demo | svc-rotate-b | Dual |
| svc-rotate-c | Vault Agent | svc-rotate-d | Dual |
| svc-rotate-e | CSI Driver | svc-rotate-f | Dual |
| svc-single | Vault Agent | - | Single |
| svc-lib | CSI Driver | - | Single |

### 4. Dual-Account Architecture

**Enabled by:** `ldap_dual_account = true`

**Key Components:**
- Custom plugin: `vault-plugin-secrets-openldap` (v0.17.0-dual-account.1)
- Custom Vault image: `ghcr.io/andybaran/vault-with-openldap-plugin:dual-account-rotation`
- Grace period: Configurable overlap time (default: 20 seconds)
- Three static role types:
  1. Demo role: `dual-rotation-demo` (svc-rotate-a ↔ svc-rotate-b)
  2. Vault Agent role: `vault-agent-dual-role` (svc-rotate-c ↔ svc-rotate-d)
  3. CSI role: `csi-dual-role` (svc-rotate-e ↔ svc-rotate-f)

**Rotation Flow:**
1. **Active State**: Primary account is current
2. **Grace Period**: Both accounts valid for configured seconds
3. **Switchover**: Secondary becomes new primary
4. **Repeat**: Next rotation cycle begins

### 5. Three Deployment Methods

#### VSO (Vault Secrets Operator)
- **Delivery**: K8s Secret (synced by VaultDynamicSecret CRD)
- **Consumption**: Environment variables from secret
- **Refresh**: Every ~80% of rotation period
- **Replicas**: 2
- **Status**: Always deployed

#### Vault Agent Sidecar
- **Delivery**: File at `/vault/secrets/ldap-creds` (env format)
- **Consumption**: App reads file, parses env vars
- **Refresh**: Init container + sidecar (30s interval)
- **Replicas**: 1
- **Status**: Dual-account mode only

#### CSI Driver
- **Delivery**: Individual files at `/vault/secrets/` + JSON response
- **Consumption**: App reads files directly
- **Refresh**: CSI driver handles automatic refresh
- **Replicas**: 1
- **Status**: Dual-account mode only

### 6. LDAP Configuration
```
Server: Windows Server 2025 with Active Directory
URL: ldaps://10.0.1.50:636 (port 636 = LDAPS)
Domain: mydomain.local
Bind DN: CN=Administrator,CN=Users,DC=mydomain,DC=local
User Base: CN=Users,DC=mydomain,DC=local
Search Attr: cn (NOT userPrincipalName)
Schema: ad (Active Directory)
TLS: Insecure (self-signed ADCS cert)
```

### 7. Kubernetes Authentication
Four K8s auth roles created:

1. **vso-role** (always)
   - Service Account: vso-auth
   - Purpose: VSO pods authenticate to Vault
   - Namespace: Variable (default "default")

2. **ldap-app-role** (dual-account only)
   - Service Account: ldap-app-vault-auth
   - Purpose: App direct polling of Vault
   - Used when app needs real-time dual-account state

3. **vault-agent-app-role** (dual-account only)
   - Service Account: ldap-app-vault-agent
   - Purpose: Vault Agent init/sidecar authentication
   - Refresh rate: Every 30s

4. **csi-app-role** (dual-account only)
   - Service Account: ldap-app-csi
   - Purpose: CSI Driver pod authentication
   - Managed by CSI provider plugin

All use Kubernetes JWT validation with local CA cert verification.

---

## Module-by-Module Breakdown

### modules/AWS_DC/
**Purpose:** Windows Server 2025 with Active Directory

**Key Outputs:**
- `dc-priv-ip`: Private IP for LDAP URL construction
- `password`: Administrator password for LDAP binding
- `static_roles`: Map of 8 test users with passwords and DNs

**Configuration:**
- Domain: mydomain.local
- NetBIOS: mydomain
- AD DS: Promoted to domain controller
- AD CS: Installed (enables LDAPS on port 636)
- Test Users: 8 accounts with random passwords

**Wait Time:** 10 minutes (AD promotion + ADCS install + user creation)

### modules/vault_ldap_secrets/
**Purpose:** Configure LDAP secrets engine and Kubernetes auth

**Single-Account Mode (main.tf):**
- Standard Vault `vault_ldap_secret_backend` resource
- Creates static roles for password rotation
- Simple 1:1 account:password mapping

**Dual-Account Mode (dual_account.tf):**
- Custom plugin registration and mount
- Three static role types (demo, vault-agent, csi)
- Each role manages 2 AD accounts

**Kubernetes Auth (kubernetes_auth.tf):**
- auth backend type: "kubernetes"
- 4 roles for different use cases
- All use local JWT validation

### modules/ldap_app/
**Purpose:** Deploy 1-3 demo apps showing different secret delivery methods

**Files:**
- `ldap_app.tf`: VSO deployment (always)
- `vault_agent_app.tf`: Vault Agent deployment (dual-account only)
- `csi_app.tf`: CSI Driver deployment (dual-account only)
- `variables.tf`: All input variables

**Key Features:**
- All apps in same namespace (configurable)
- All exposed via LoadBalancer services
- Each sets `SECRET_DELIVERY_METHOD` env var differently
- Dual-account deployments set additional vars
- Health checks (liveness + readiness probes)

### modules/vault/
**Purpose:** Deploy Vault HA cluster

**Files:**
- `vault.tf`: Helm chart deployment (3 replicas)
- `vault_init.tf`: Initialization job + unsealing
- `csi_driver.tf`: CSI integration resources
- `storage.tf`: EBS storage class
- `variables.tf`: Configuration

**Key Features:**
- HA + Raft consensus storage
- Persistent volumes (EBS gp3)
- LoadBalancer services for API and UI
- Auto-initialization and unsealing
- Plugin directory enabled when dual-account=true

---

## Critical Wiring Points

### Must Maintain for OpenLDAP Compatibility:

1. **LDAP URL Format**: `ldaps://<server-ip>:636`
   - Change: Server IP/hostname, TLS settings if needed
   - Keep: URL construction method

2. **Bind Authentication**: Service account with change password rights
   - Change: Bind DN format (OpenLDAP style)
   - Change: Bind password source
   - Keep: Used for rotation operations

3. **User Search Configuration**: Base DN + attribute
   - Change: May use `uid` instead of `cn`
   - Change: Userdn format for OpenLDAP schema
   - Keep: Attribute configuration pattern

4. **Static Role Definitions**: List of users to rotate
   - Change: User DNs (OpenLDAP format)
   - Change: User naming conventions
   - Keep: Output structure and mapping

5. **Kubernetes Integration**: Unchanged
   - Keep: Auth method, roles, policies
   - Keep: Service account binding
   - Keep: JWT validation

---

## Environment Variables by Deployment Method

### All Methods Include:
```
SECRET_DELIVERY_METHOD = vault-secrets-operator | vault-agent-sidecar | vault-csi-driver
LDAP_USERNAME
LDAP_PASSWORD
LDAP_LAST_VAULT_PASSWORD
ROTATION_PERIOD
ROTATION_TTL
```

### Dual-Account Additional Fields:
```
DUAL_ACCOUNT_MODE = true
ACTIVE_ACCOUNT = primary | secondary
ROTATION_STATE = active | grace_period
STANDBY_USERNAME (only during grace_period)
STANDBY_PASSWORD (only during grace_period)
GRACE_PERIOD_END (only during grace_period)
GRACE_PERIOD = <seconds>
```

### Method-Specific Config:
```
VSO:
  VAULT_ADDR (for polling)
  VAULT_AUTH_ROLE (for polling)
  LDAP_MOUNT_PATH
  LDAP_STATIC_ROLE_NAME

Vault Agent:
  SECRETS_FILE_PATH = /vault/secrets/ldap-creds
  VAULT_ADDR
  VAULT_AUTH_ROLE

CSI Driver:
  SECRETS_FILE_PATH = /vault/secrets
  VAULT_ADDR (optional, for polling)
  VAULT_AUTH_ROLE (optional, for polling)
```

---

## Single-Account vs Dual-Account

### Single-Account Mode (ldap_dual_account=false)

**Vault Engine:**
- Type: `ldap` (built-in)
- Plugin: None

**Deployments:**
- VSO only
- No Vault Agent
- No CSI Driver

**Response Fields:**
```
username, password, last_vault_rotation, rotation_period, ttl
```

**Use Case:**
- Simple password rotation
- One account per role
- Immediate password override

### Dual-Account Mode (ldap_dual_account=true)

**Vault Engine:**
- Type: `ldap_dual_account` (custom plugin)
- Plugin: vault-plugin-secrets-openldap v0.17.0-dual-account.1
- Image: ghcr.io/andybaran/vault-with-openldap-plugin:dual-account-rotation

**Deployments:**
- VSO (demo)
- Vault Agent (sidecar)
- CSI Driver

**Response Fields:**
```
username, password, standby_username, standby_password,
active_account, rotation_state, grace_period_end,
last_vault_rotation, rotation_period, ttl, dual_account_mode
```

**Use Case:**
- Zero-downtime password rotation
- Two accounts per role
- Grace period for transition
- Client-controlled switchover timing

---

## Provider Versions

```
aws: 6.27.0
vault: 5.6.0
kubernetes: 3.0.1
helm: 3.1.1
tls: ~4.0.5
random: ~3.6.0
http: ~3.5.0
cloudinit: 2.3.7
null: 3.2.4
time: 0.13.1
```

---

## Deployment Sequence

1. **kube0** (EKS) → Outputs: cluster_endpoint, VPC, security groups
2. **kube1** (K8s tools) → Outputs: namespace, VaultAuth CRD
3. **vault_cluster** (Helm) → Outputs: root token, LB hostname
4. **ldap** (AD DC) → Outputs: dc-priv-ip, password, static_roles (10 min wait)
5. **vault_ldap_secrets** (Config) → Outputs: mount path, role names
6. **ldap_app** (Apps) → Uses all above

**Parallel Deployments:** vault_cluster and ldap can deploy simultaneously.

---

## For OpenLDAP Implementation

### What to Change:
1. Replace AWS_DC module with OpenLDAP server/container
2. Update LDAP connection parameters
3. Adjust user search base and attribute for OpenLDAP schema
4. Update service account bind DN format
5. Create equivalent test users

### What to Keep Unchanged:
1. Vault LDAP secrets engine configuration pattern
2. Static role definitions and structure
3. Kubernetes authentication backend
4. All three deployment methods (VSO, Agent, CSI)
5. Dual-account rotation mechanism
6. Provider configurations
7. Application deployments

### Key Output Requirements:
Ensure OpenLDAP module outputs same structure:
```hcl
output "dc-priv-ip" { value = <ldap-server-ip> }
output "password" { value = <bind-account-password> }
output "static_roles" {
  value = {
    "user1": { username = "...", password = "...", dn = "..." },
    "user2": { username = "...", password = "...", dn = "..." },
    ...
  }
}
```

---

## Files Created

| File | Lines | Purpose |
|------|-------|---------|
| ARCHITECTURE_ANALYSIS.md | 1221 | Complete technical reference |
| QUICK_REFERENCE.md | 430+ | Quick lookup guide |
| EXPLORATION_SUMMARY.md | This | High-level overview |

**Location:** `/Users/andy.baran/code/aws-vault-ldap-k8s/`

---

## Key Takeaways

1. **Modular Design**: Components are well-separated with clear inputs/outputs
2. **Dual-Account Support**: Custom plugin enables zero-downtime rotations
3. **Multiple Delivery Methods**: VSO, Agent, and CSI demonstrate different approaches
4. **Kubernetes-Native**: Uses K8s auth, CRDs, and service accounts
5. **Enterprise Ready**: HA Vault, Raft storage, persistent volumes
6. **Extensible**: OpenLDAP can replace AD with minimal changes

---

**Exploration completed:** $(date)
**Documentation**: Ready for review and implementation
**Next step**: Use this architecture to create compatible OpenLDAP module

