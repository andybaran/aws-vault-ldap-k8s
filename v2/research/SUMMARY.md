# RESEARCH SUMMARY: OpenLDAP on Kubernetes & Vault LDAP Integration

## Key Findings

### 1. OpenLDAP Docker Images for Kubernetes

| Image | Use Case | Recommendation |
|-------|----------|----------------|
| **osixia/openldap** | Dev/Test + HashiCorp tutorials | ✅ Start here (lightweight) |
| **bitnami/openldap** | Production deployments | ✅ Recommended for enterprise |
| **Official OpenLDAP** | Minimal custom builds | ⚠️ Rarely used for K8s |

**Winner for EKS:** Bitnami OpenLDAP (production-ready with Helm chart)

### 2. Running OpenLDAP on EKS

✅ **YES - Fully Supported**
- Use **StatefulSet** (not Deployment) for persistent data
- **EBS Persistent Volumes** (gp3 recommended for AWS EKS)
- Resource requests: 250m CPU, 256Mi RAM (minimum)
- Health checks: liveness + readiness probes on port 389
- Cluster IP Service for internal access (optional: LoadBalancer for external)

**Example:** 1-node StatefulSet with 10Gi EBS volume, fully HA-capable

---

### 3. OpenLDAP + Vault LDAP Secrets Engine

#### Schema Configuration
| Aspect | OpenLDAP | Active Directory (Your Project) |
|--------|----------|------|
| **Vault Schema** | `schema = "openldap"` | `schema = "ad"` |
| **Default userattr** | `cn` | `sAMAccountName` (you override to `cn`) |
| **Bind DN Format** | `cn=admin,dc=example,dc=com` | `CN=Administrator,CN=Users,DC=mydomain,DC=local` |
| **User DN Base** | `ou=users,dc=example,dc=com` | `CN=Users,DC=mydomain,DC=local` |
| **Password Attribute** | `userPassword` | `unicodePwd` |
| **Object Class** | `inetOrgPerson` | `user` |
| **Connection Security** | Optional (LDAP or LDAPS) | **LDAPS REQUIRED** for password ops |
| **Default Port** | 389 (LDAP), 636 (LDAPS) | 636 (LDAPS only) |

#### Configuration Example for OpenLDAP
```hcl
resource "vault_ldap_secret_backend" "openldap" {
  path        = "ldap"
  schema      = "openldap"
  url         = "ldap://openldap.ldap.svc.cluster.local:389"
  binddn      = "cn=admin,dc=example,dc=com"
  bindpass    = "admin_password"
  userdn      = "ou=users,dc=example,dc=com"
  userattr    = "cn"  # OpenLDAP standard
}
```

---

### 4. Bitnami OpenLDAP Helm Chart Key Values

```yaml
# Minimal production-ready values
image:
  repository: bitnami/openldap
  tag: "2.6.8"

auth:
  adminPassword: "changeme123!"
  configPassword: "config_pass123!"
  bindDN: "cn=bind-user,dc=example,dc=com"
  bindPassword: "bind_pass123!"

ldap:
  baseDN: "dc=example,dc=com"
  domain: "example.com"
  customLdifFiles:
    01-users.ldif: |
      dn: cn=vault-admin,ou=users,dc=example,dc=com
      objectClass: inetOrgPerson
      cn: vault-admin
      sn: Admin
      userPassword: VaultPassword123!

persistence:
  enabled: true
  size: 8Gi
  storageClass: "gp3"

service:
  type: ClusterIP
  port: 389
  portSSL: 636

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi
```

**Install:**
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install openldap bitnami/openldap \
  --namespace ldap --create-namespace \
  -f values.yaml
```

---

### 5. Your Custom Vault Plugin: `vault-plugin-secrets-openldap`

**Plugin Details:**
- **Purpose:** Dual-account (blue/green) password rotation
- **Compatibility:** Works with BOTH OpenLDAP AND Active Directory ✅
- **Image:** `ghcr.io/andybaran/vault-with-openldap-plugin:dual-account-rotation`
- **SHA256:** `e71b4bec10963fe5f704d710f34be5a933330126799541fd1bd7b0e3536a8dad`
- **Version:** v0.17.0-dual-account.1

**How It Works:**
```
Standard Rotation (30s):
Account A (v1) → [rotate] → Account A (v2) ❌ OLD PASSWORD BREAKS APPS

Dual-Account Rotation (30s + grace period):
Account A (v1) → [rotate B to v2] → Both work → [rotate A to v3] → Account B is now primary
✅ ZERO-DOWNTIME PASSWORD ROTATION
```

**Configuration for OpenLDAP:**
```hcl
resource "vault_generic_endpoint" "ldap_config" {
  path = "ldap/config"
  data_json = jsonencode({
    url      = "ldap://openldap.ldap.svc.cluster.local:389"
    binddn   = "cn=admin,dc=example,dc=com"
    bindpass = "admin_password"
    schema   = "openldap"  # Change from "ad" to "openldap"
    userattr = "cn"
    userdn   = "ou=users,dc=example,dc=com"
  })
}

resource "vault_generic_endpoint" "dual_role" {
  path = "ldap/static-role/db-service"
  data_json = jsonencode({
    username          = "db-service-a"
    dn                = "cn=db-service-a,ou=users,dc=example,dc=com"
    username_b        = "db-service-b"
    dn_b              = "cn=db-service-b,ou=users,dc=example,dc=com"
    rotation_period   = "3600s"
    grace_period      = "300s"
    dual_account_mode = true
  })
}
```

---

### 6. AD vs OpenLDAP Configuration Comparison

**Your Project's Current Setup (AD):**
```hcl
resource "vault_ldap_secret_backend" "ad" {
  schema   = "ad"
  url      = "ldaps://10.0.0.5:636"  # LDAPS required
  binddn   = "CN=Administrator,CN=Users,DC=mydomain,DC=local"
  userdn   = "CN=Users,DC=mydomain,DC=local"
  userattr = "cn"  # You override default (sAMAccountName)
  insecure_tls = true
}
```

**For OpenLDAP - Just Change These Values:**
```hcl
resource "vault_ldap_secret_backend" "openldap" {
  schema   = "openldap"  # ← Change
  url      = "ldap://openldap.ldap.svc.cluster.local:389"  # ← Change
  binddn   = "cn=admin,dc=example,dc=com"  # ← Change (DN format)
  userdn   = "ou=users,dc=example,dc=com"  # ← Change (DN format)
  userattr = "cn"  # ← Keep the same
  # insecure_tls = false  # ← Optional TLS settings
}
```

**Static Role Creation is IDENTICAL:**
```hcl
resource "vault_ldap_secret_backend_static_role" "roles" {
  mount           = vault_ldap_secret_backend.openldap.path
  role_name       = "vault-admin"
  username        = "vault-admin"
  rotation_period = 30
  skip_import_rotation = false
}

# Read rotated password
# vault read ldap/static-cred/vault-admin
# Returns: { "username": "vault-admin", "password": "new_password" }
```

---

## Quick Migration Checklist: AD → OpenLDAP

- [ ] Deploy OpenLDAP on EKS (Bitnami Helm chart)
- [ ] Create users in OpenLDAP LDIF files (e.g., `vault-admin`, `db-service-a`, `db-service-b`)
- [ ] Change Vault configuration:
  - [ ] `schema = "openldap"`
  - [ ] `url` to OpenLDAP service DNS
  - [ ] `binddn` to OpenLDAP admin DN format
  - [ ] `userdn` to OpenLDAP organizational unit
- [ ] Update static role definitions (just change `username` and `dn` fields)
- [ ] Test Vault → OpenLDAP connectivity: `vault read ldap/config`
- [ ] Verify password rotation: `vault read ldap/static-cred/vault-admin`
- [ ] Update dual-account plugin config (if using `ldap_dual_account = true`)

---

## Key Conclusions

✅ **OpenLDAP on EKS:** Fully production-ready with Bitnami Helm chart
✅ **Your Plugin:** Works seamlessly with OpenLDAP (backend-agnostic)
✅ **Configuration:** Simple schema/userattr changes to switch from AD
✅ **Reliability:** Standard Linux nodes + EBS volumes = enterprise-grade
✅ **Cost:** Kubernetes-native OpenLDAP cheaper than Windows EC2 infrastructure

**Your project is architecture-agnostic** — the Vault LDAP secrets engine + dual-account plugin work identically with both AD and OpenLDAP. Just adjust the connection parameters!

