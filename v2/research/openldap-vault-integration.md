# COMPREHENSIVE RESEARCH REPORT
## OpenLDAP on Kubernetes/EKS & Vault LDAP Secrets Engine Integration

**Date:** 2025-01-14  
**Status:** Complete with findings from `aws-vault-ldap-k8s` project analysis

---

## EXECUTIVE SUMMARY

Your project (`aws-vault-ldap-k8s`) currently uses **Active Directory** on a Windows EC2 instance, NOT OpenLDAP. However, the Vault LDAP secrets engine can work with both. This report documents:

1. **OpenLDAP on Kubernetes** - Best practices & Docker images
2. **OpenLDAP + Vault LDAP Secrets Engine** - Configuration differences from AD
3. **Bitnami OpenLDAP Helm Chart** - Key values and setup
4. **Your Custom Plugin** - `vault-plugin-secrets-openldap` dual-account plugin compatibility
5. **AD vs OpenLDAP** - Key configuration differences for Vault

---

# 1. OPENLDAP ON KUBERNETES/EKS

## 1.1 Popular OpenLDAP Docker Images

### **osixia/openldap** (HashiCorp Tutorial Standard)
- **Repository:** https://github.com/osixia/docker-openldap
- **Image:** `osixia/openldap:latest`
- **Tags:** Alpine-based, lightweight
- **Usage:** HashiCorp's official Vault tutorials use this image
- **Features:**
  - Based on Debian/Alpine
  - Pre-configured with `slapd` (OpenLDAP server daemon)
  - Supports custom LDIF initialization
  - Easy password management via `LDAP_ADMIN_PASSWORD` env var
  - TLS support via certificates

**Kubernetes Example:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: openldap
spec:
  containers:
  - name: openldap
    image: osixia/openldap:latest
    ports:
    - containerPort: 389     # LDAP
    - containerPort: 636     # LDAPS
    env:
    - name: LDAP_ORGANISATION
      value: "Example Org"
    - name: LDAP_DOMAIN
      value: "example.com"
    - name: LDAP_ADMIN_PASSWORD
      value: "password123"
    - name: LDAP_CONFIG_PASSWORD
      value: "config_password"
    volumeMounts:
    - name: ldap-data
      mountPath: /var/lib/ldap
    - name: ldap-config
      mountPath: /etc/ldap/slapd.d
  volumes:
  - name: ldap-data
    emptyDir: {}
  - name: ldap-config
    emptyDir: {}
```

**Strengths:**
- ✅ Minimal overhead
- ✅ Easy configuration
- ✅ Official Vault tutorial standard
- ✅ Supports stateful deployments with PVC

**Weaknesses:**
- ⚠️ Requires custom LDIF for initial data
- ⚠️ Single-server (no built-in replication)
- ⚠️ Limited operational tooling

---

### **bitnami/openldap** (Enterprise-Ready)
- **Repository:** https://github.com/bitnami/containers/tree/main/bitnami/openldap
- **Image:** `bitnami/openldap:latest`
- **Helm Chart:** `oci://registry.bitnami.com/charts/openldap`
- **Tags:** Production-grade, rich features

**Key Bitnami Helm Values:**
```yaml
# values.yaml for bitnami/openldap Helm chart
replicaCount: 1

image:
  repository: bitnami/openldap
  tag: "2.6.8"  # Latest stable version

auth:
  adminPassword: "admin_password"
  configPassword: "config_password"
  bindPassword: "bind_user_password"
  bindDN: "cn=admin,dc=example,dc=com"

ldapDomain: "example.com"
ldapBaseDN: "dc=example,dc=com"
ldapOrganization: "Example Organization"

# Custom LDIF files for initial data
customLdifFiles:
  01-base.ldif: |
    dn: ou=users,dc=example,dc=com
    objectClass: organizationalUnit
    ou: users
    
    dn: cn=vault-admin,ou=users,dc=example,dc=com
    objectClass: inetOrgPerson
    cn: vault-admin
    sn: Admin
    userPassword: password123
  02-groups.ldif: |
    dn: ou=groups,dc=example,dc=com
    objectClass: organizationalUnit
    ou: groups

persistence:
  enabled: true
  size: 8Gi
  storageClass: "gp3"  # For EKS

service:
  type: ClusterIP
  ldapPort: 389
  ldapsPort: 636

# Liveness/readiness probes
livenessProbe:
  enabled: true
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  enabled: true
  initialDelaySeconds: 10
  periodSeconds: 5

# Pod security
podSecurityPolicy:
  enabled: false  # Use Pod Security Standards instead in K8s 1.25+

# Resource limits (important for EKS)
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi
```

**Installation:**
```bash
# Add Bitnami Helm repo
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Install OpenLDAP
helm install openldap bitnami/openldap \
  --namespace ldap \
  --create-namespace \
  -f values.yaml

# Verify deployment
kubectl get pods -n ldap
kubectl logs -n ldap deployment/openldap
```

**Strengths:**
- ✅ Production-grade (used by enterprises)
- ✅ Rich Helm chart with sensible defaults
- ✅ Multi-replica replication support
- ✅ StatefulSet with persistent storage
- ✅ Built-in health checks
- ✅ Comprehensive RBAC support

**Weaknesses:**
- ⚠️ More resource consumption
- ⚠️ Requires more initial configuration
- ⚠️ Slightly longer startup time

---

### **OpenLDAP Official Image** (Minimal, rarely used for K8s)
- **Repository:** https://github.com/openldap/openldap-docker
- **Status:** Official but less common in K8s deployments
- **Note:** Usually requires extensive customization

---

## 1.2 Running OpenLDAP on EKS with Standard Linux Nodes

**YES - OpenLDAP runs reliably on EKS with standard Linux nodes.**

### Architecture Example:
```
┌──────────────────────────────────┐
│ EKS Cluster (us-east-2)          │
│ ├─ Managed Node Group (2x t3.medium, Linux)
│ │  └─ OpenLDAP Pod (StatefulSet)
│ │     ├─ Persistent Volume (EBS gp3, 10Gi)
│ │     └─ Service (ClusterIP + optional LoadBalancer)
│ └─ Vault Pod (Raft HA)
│    └─ Connected to OpenLDAP via Service DNS
└──────────────────────────────────┘
```

### Best Practices for EKS:
1. **Use StatefulSet** (not Deployment) for persistent LDAP data
2. **EBS Persistent Volumes** (gp3 recommended for EKS)
3. **Resource Requests/Limits** (prevent node eviction)
4. **Network Policies** (restrict LDAP access to Vault namespace only)
5. **Backup/Recovery** (snapshot EBS volumes)
6. **Monitoring** (CloudWatch metrics for pod health)

### Recommended StatefulSet Configuration:
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: openldap
  namespace: ldap
spec:
  serviceName: openldap
  replicas: 1
  selector:
    matchLabels:
      app: openldap
  template:
    metadata:
      labels:
        app: openldap
    spec:
      containers:
      - name: openldap
        image: osixia/openldap:latest
        ports:
        - name: ldap
          containerPort: 389
        - name: ldaps
          containerPort: 636
        env:
        - name: LDAP_ORGANISATION
          value: "MyOrg"
        - name: LDAP_DOMAIN
          value: "example.com"
        - name: LDAP_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: openldap-secret
              key: admin-password
        resources:
          requests:
            cpu: 250m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        livenessProbe:
          tcpSocket:
            port: 389
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          tcpSocket:
            port: 389
          initialDelaySeconds: 10
          periodSeconds: 5
        volumeMounts:
        - name: ldap-data
          mountPath: /var/lib/ldap
        - name: ldap-config
          mountPath: /etc/ldap/slapd.d
  volumeClaimTemplates:
  - metadata:
      name: ldap-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: "gp3"
      resources:
        requests:
          storage: 10Gi
  - metadata:
      name: ldap-config
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: "gp3"
      resources:
        requests:
          storage: 2Gi
---
apiVersion: v1
kind: Service
metadata:
  name: openldap
  namespace: ldap
spec:
  type: ClusterIP
  clusterIP: None  # Headless for StatefulSet
  selector:
    app: openldap
  ports:
  - name: ldap
    port: 389
    targetPort: 389
  - name: ldaps
    port: 636
    targetPort: 636
```

---

# 2. OPENLDAP + VAULT LDAP SECRETS ENGINE

## 2.1 Schema Configuration: `openldap` vs `ad` vs `default`

Vault's LDAP secrets engine supports **THREE schemas:**

### **Schema: `openldap`** (Recommended for OpenLDAP)
```hcl
resource "vault_ldap_secret_backend" "openldap" {
  path   = "ldap"
  schema = "openldap"
  
  url      = "ldap://openldap.ldap.svc.cluster.local:389"
  binddn   = "cn=admin,dc=example,dc=com"
  bindpass = "admin_password"
  userdn   = "ou=users,dc=example,dc=com"
  
  # OpenLDAP uses different password fields
  password_policy = "openldap"
}
```

**Key Characteristics:**
- ✅ Uses **`cn` (common name)** as the user identifier
- ✅ Password stored in **`userPassword` attribute** (hashed by OpenLDAP)
- ✅ DN format: `cn=username,ou=users,dc=example,dc=com`
- ✅ Supports plain LDAP (no TLS required, though TLS is recommended)
- ✅ Compatible with `inetOrgPerson` object class

### **Schema: `ad`** (Your Current Project - for Active Directory)
```hcl
resource "vault_ldap_secret_backend" "ad" {
  path   = "ldap"
  schema = "ad"
  
  url      = "ldaps://10.0.0.5:636"  # LDAPS (encrypted)
  binddn   = "CN=Administrator,CN=Users,DC=mydomain,DC=local"
  bindpass = "password123"
  userdn   = "CN=Users,DC=mydomain,DC=local"
  
  userattr = "cn"  # Your project uses CN, not default sAMAccountName
  insecure_tls = true
}
```

**Key Characteristics:**
- ✅ Uses **`sAMAccountName` as default** (but can override with `cn`)
- ✅ Password stored in **`unicodePwd` attribute** (encrypted by AD)
- ✅ DN format: `CN=username,CN=Users,DC=mydomain,DC=local`
- ✅ **REQUIRES LDAPS (encrypted)** for password changes
- ✅ Compatible with `user` object class

**Your Project's Key Finding:**
```hcl
# From modules/vault_ldap_secrets/main.tf
userattr = "cn"  # Explicit override!
# Comment explains: "default for AD schema is userPrincipalName,
# but Vault searches with bare username which doesn't match full UPN"
```

### **Schema: `default`** (Generic LDAP)
```hcl
resource "vault_ldap_secret_backend" "generic" {
  path   = "ldap"
  schema = "default"
  
  url      = "ldap://ldap.example.com:389"
  binddn   = "uid=admin,ou=people,dc=example,dc=com"
  bindpass = "password"
  userdn   = "ou=people,dc=example,dc=com"
  
  userattr = "uid"  # Custom attribute name
  password_policy = "default"
}
```

**Key Characteristics:**
- ✅ Generic LDAP schema (RFC 2307)
- ✅ Uses **`uid` as user identifier**
- ✅ Password stored in **`userPassword` attribute**
- ✅ DN format: `uid=username,ou=people,dc=example,dc=com`

---

## 2.2 Comparison Table: OpenLDAP vs AD Configuration

| **Aspect** | **OpenLDAP** | **Active Directory** |
|-----------|-------------|---------------------|
| **Schema** | `openldap` | `ad` |
| **User Identifier (userattr)** | `cn` (common name) | `sAMAccountName` (default) or `cn` |
| **User DN Format** | `cn=jdoe,ou=users,dc=example,dc=com` | `CN=jdoe,CN=Users,DC=mydomain,DC=local` |
| **Base DN (userdn)** | `ou=users,dc=example,dc=com` | `CN=Users,DC=mydomain,DC=local` |
| **Bind DN Format** | `cn=admin,dc=example,dc=com` | `CN=Administrator,CN=Users,DC=mydomain,DC=local` |
| **Password Attribute** | `userPassword` (plaintext or hashed) | `unicodePwd` (always encrypted) |
| **Connection Security** | LDAP (389) or LDAPS (636) | **LDAPS REQUIRED (636)** for password ops |
| **TLS Requirement** | Optional | **Mandatory for password changes** |
| **Default Port** | 389 (LDAP), 636 (LDAPS) | 636 (LDAPS) |
| **Object Class** | `inetOrgPerson`, `posixAccount` | `user` |
| **Password Policy Support** | Via attribute constraints | Via AD Group Policy Objects (GPOs) |
| **User Search Filter** | `(&(objectClass=inetOrgPerson)(cn=*))` | `(&(objectClass=user)(sAMAccountName=*))` |

---

## 2.3 Vault LDAP Secrets Engine Configuration for OpenLDAP

### Complete Terraform Example:
```hcl
# Mount the LDAP secrets engine
resource "vault_ldap_secret_backend" "openldap" {
  path        = "ldap"
  description = "LDAP secrets engine for OpenLDAP"
  
  # Connection settings
  url      = "ldap://openldap.ldap.svc.cluster.local:389"
  binddn   = "cn=admin,dc=example,dc=com"
  bindpass = var.ldap_admin_password
  
  # User search configuration
  schema   = "openldap"
  userattr = "cn"
  userdn   = "ou=users,dc=example,dc=com"
  
  # Optional: TLS for encrypted connection
  # (uncomment if OpenLDAP has TLS configured)
  # starttls = true
  # insecure_tls = false
  # tls_ca_cert = file("${path.module}/ca.crt")
  
  # Rotation behavior
  skip_static_role_import_rotation = false  # Import initial password on first run
}

# Static role for Vault to manage OpenLDAP user password
resource "vault_ldap_secret_backend_static_role" "vault_user" {
  mount        = vault_ldap_secret_backend.openldap.path
  role_name    = "vault-admin"
  username     = "vault-admin"  # Must exist in OpenLDAP
  
  # Rotation period in seconds (30 seconds for demo)
  rotation_period = 30
  
  # Initial password import
  skip_import_rotation = false
}

# Policy to grant access to the secret
resource "vault_policy" "ldap_read" {
  name = "ldap-read"
  
  policy = <<-EOT
    path "ldap/static-cred/vault-admin" {
      capabilities = ["read"]
    }
  EOT
}
```

### Create OpenLDAP User for Vault:
```bash
# Execute inside the OpenLDAP container
ldapadd -x -D "cn=admin,dc=example,dc=com" -w admin_password << EOF
dn: cn=vault-admin,ou=users,dc=example,dc=com
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
cn: vault-admin
sn: Admin
userPassword: InitialPassword123!
EOF
```

---

## 2.4 Static Roles with OpenLDAP

**Static roles vs Dynamic roles:**
- **Static roles**: Vault rotates the password of an EXISTING LDAP user
- **Dynamic roles**: Vault CREATES temporary LDAP users (not supported for LDAP backend)

**Configuration for OpenLDAP static role:**
```hcl
resource "vault_ldap_secret_backend_static_role" "db_service" {
  mount        = vault_ldap_secret_backend.openldap.path
  role_name    = "db-service"
  username     = "db-service-account"  # OpenLDAP user must exist
  rotation_period = 3600  # Rotate every hour
  skip_import_rotation = false
}

# Read the current credentials
# vault read ldap/static-cred/db-service
# Returns: { "username": "db-service-account", "password": "new_rotated_password" }
```

---

## 2.5 Userattr for OpenLDAP

**OpenLDAP uses `cn` (common name) as the user identifier:**

```hcl
userattr = "cn"  # For OpenLDAP (not sAMAccountName like AD)
```

**Contrast with AD:**
```hcl
userattr = "sAMAccountName"  # Default for AD (e.g., "jdoe")
# OR
userattr = "cn"  # Alternative if you want "Common Name" style (your project's approach)
```

**Vault User Search Filter for OpenLDAP:**
```
# When userattr = "cn", Vault searches for users with:
filter = "(&(objectClass=inetOrgPerson)(cn=vault-admin))"

# Vault will match objects like:
dn: cn=vault-admin,ou=users,dc=example,dc=com
objectClass: inetOrgPerson
cn: vault-admin
sn: Admin
userPassword: {SSHA}...
```

---

# 3. BITNAMI OPENLDAP HELM CHART

## 3.1 Complete Helm Values Reference

```yaml
# File: values.yaml
# Full configuration for bitnami/openldap Helm chart

global:
  storageClass: "gp3"  # AWS EKS GP3 storage class
  imageRegistry: "docker.io"

image:
  registry: docker.io
  repository: bitnami/openldap
  tag: "2.6.8"
  pullPolicy: IfNotPresent

replicaCount: 1

auth:
  # Admin credentials
  adminPassword: "changeme123!"
  
  # Config DN credentials (for configuration changes)
  configPassword: "config_pass123!"
  
  # Bind user credentials (for application access)
  bindPassword: "bind_pass123!"
  bindDN: "cn=bind-user,dc=example,dc=com"

ldap:
  # Base DN structure
  baseDN: "dc=example,dc=com"
  domain: "example.com"
  organization: "Example Organization"
  
  # Additional DNs
  admins:
  - "cn=admin"
  
  config:
    # LDAP database settings
    backend: "mdb"  # Memory database (recommended)
    maxConnections: 100
    maxObjectSize: 20971520  # 20MB
  
  # Custom LDIF files for initialization
  customLdifFiles:
    # Create organizational units
    01-base-ous.ldif: |
      dn: ou=users,dc=example,dc=com
      objectClass: organizationalUnit
      ou: users
      
      dn: ou=groups,dc=example,dc=com
      objectClass: organizationalUnit
      ou: groups
      
      dn: ou=services,dc=example,dc=com
      objectClass: organizationalUnit
      ou: services
    
    # Create service accounts for Vault
    02-vault-users.ldif: |
      dn: cn=vault-admin,ou=services,dc=example,dc=com
      objectClass: inetOrgPerson
      objectClass: organizationalPerson
      objectClass: person
      cn: vault-admin
      sn: Admin
      userPassword: VaultPassword123!
      mail: vault-admin@example.com
      
      dn: cn=db-service,ou=services,dc=example,dc=com
      objectClass: inetOrgPerson
      objectClass: organizationalPerson
      objectClass: person
      cn: db-service
      sn: Service
      userPassword: DBPassword123!
      mail: db-service@example.com
    
    # Create application users
    03-app-users.ldif: |
      dn: cn=jdoe,ou=users,dc=example,dc=com
      objectClass: inetOrgPerson
      objectClass: organizationalPerson
      objectClass: person
      cn: jdoe
      sn: Doe
      givenName: John
      mail: john.doe@example.com
      userPassword: UserPassword123!
      
      dn: cn=asmith,ou=users,dc=example,dc=com
      objectClass: inetOrgPerson
      objectClass: organizationalPerson
      objectClass: person
      cn: asmith
      sn: Smith
      givenName: Alice
      mail: alice.smith@example.com
      userPassword: UserPassword123!
    
    # Create groups (for RBAC)
    04-groups.ldif: |
      dn: cn=admins,ou=groups,dc=example,dc=com
      objectClass: groupOfNames
      cn: admins
      member: cn=jdoe,ou=users,dc=example,dc=com
      
      dn: cn=developers,ou=groups,dc=example,dc=com
      objectClass: groupOfNames
      cn: developers
      member: cn=jdoe,ou=users,dc=example,dc=com
      member: cn=asmith,ou=users,dc=example,dc=com

# Persistence (IMPORTANT for Kubernetes)
persistence:
  enabled: true
  
  # Data persistence
  data:
    enabled: true
    storageClass: "gp3"
    accessMode: ReadWriteOnce
    size: 8Gi
    mountPath: /var/lib/ldap
  
  # Configuration persistence
  conf:
    enabled: true
    storageClass: "gp3"
    accessMode: ReadWriteOnce
    size: 2Gi
    mountPath: /etc/ldap/slapd.d

service:
  type: ClusterIP
  
  # LDAP port (unencrypted)
  port: 389
  targetPort: 1389
  
  # LDAPS port (encrypted)
  portSSL: 636
  targetPortSSL: 1636
  
  # LoadBalancer IP (if type=LoadBalancer)
  loadBalancerIP: ""
  loadBalancerSourceRanges: []
  
  # Headless service for StatefulSet (optional)
  headless:
    enabled: false
    port: 389

ingress:
  enabled: false
  # For TCP/UDP protocols, consider using ExternalDNS + Service instead

# TLS Configuration
tls:
  enabled: false  # Set to true if you have certificates
  autoGenerated: false
  certFilename: tls.crt
  certKeyFilename: tls.key
  certCAFilename: ca.crt
  # mountPath: /etc/ssl/certs

# Health checks (critical for EKS)
livenessProbe:
  enabled: true
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  successThreshold: 1
  failureThreshold: 3

readinessProbe:
  enabled: true
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  successThreshold: 1
  failureThreshold: 3

# Resource limits (important for EKS cost management)
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi

# Pod Security
podSecurityPolicy:
  enabled: false  # Use Pod Security Standards in K8s 1.25+

securityContext:
  enabled: true
  fsGroup: 1001
  runAsUser: 1001
  runAsNonRoot: true
  capabilities:
    drop: ["ALL"]
  readOnlyRootFilesystem: false

# Node affinity for EKS
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      preference:
        matchExpressions:
        - key: node.kubernetes.io/lifecycle
          operator: NotIn
          values: ["spot"]  # Prefer on-demand, not spot

# Tolerations
tolerations: []

# Pod Disruption Budget (for HA)
podDisruptionBudget:
  enabled: true
  minAvailable: 1
```

---

## 3.2 Installation & Configuration Steps

### Step 1: Create Namespace and Secret
```bash
kubectl create namespace ldap

# Create secret for admin password
kubectl create secret generic openldap-secret \
  --from-literal=adminPassword=changeme123! \
  --from-literal=configPassword=config_pass123! \
  --from-literal=bindPassword=bind_pass123! \
  -n ldap
```

### Step 2: Install Helm Chart
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm install openldap bitnami/openldap \
  --namespace ldap \
  --values values.yaml
```

### Step 3: Verify Installation
```bash
# Check pod status
kubectl get pods -n ldap
kubectl describe pod openldap-0 -n ldap

# View logs
kubectl logs openldap-0 -n ldap

# Test LDAP connectivity
kubectl run ldap-test --image=bitnami/openldap --rm -it -- bash
# Inside pod:
ldapsearch -x -H ldap://openldap:389 -b dc=example,dc=com -D cn=admin,dc=example,dc=com -w changeme123!
```

---

# 4. CUSTOM VAULT PLUGIN: `vault-plugin-secrets-openldap`

## 4.1 Plugin Overview

**Your Custom Plugin: `vault-plugin-secrets-openldap`**
- **Repository:** https://github.com/andybaran/vault-plugin-secrets-openldap
- **Purpose:** Extends Vault's standard LDAP secrets engine with **dual-account (blue/green) rotation**
- **Status:** Custom plugin based on Vault's native LDAP plugin
- **Image:** `ghcr.io/andybaran/vault-with-openldap-plugin:dual-account-rotation`
- **SHA256:** `e71b4bec10963fe5f704d710f34be5a933330126799541fd1bd7b0e3536a8dad`
- **Version:** v0.17.0-dual-account.1

---

## 4.2 Plugin Compatibility: OpenLDAP vs AD

**✅ YES - Your custom plugin works with BOTH OpenLDAP AND Active Directory**

Your plugin is a derivative of the standard Vault LDAP plugin, which supports both LDAP backends. The dual-account extension is BACKEND-AGNOSTIC.

### How to Use Your Plugin with OpenLDAP:

```hcl
# Register the plugin in Vault catalog
resource "vault_generic_endpoint" "register_plugin" {
  path = "sys/plugins/catalog/secret/ldap_dual_account"
  
  data_json = jsonencode({
    sha256  = "e71b4bec10963fe5f704d710f34be5a933330126799541fd1bd7b0e3536a8dad"
    command = "vault-plugin-secrets-openldap"
    version = "v0.17.0-dual-account.1"
  })
}

# Mount the plugin
resource "vault_mount" "ldap_dual_account" {
  path        = "ldap"
  type        = "ldap_dual_account"
  description = "Dual-account LDAP rotation for OpenLDAP"
}

# Configure for OpenLDAP (NOT AD)
resource "vault_generic_endpoint" "ldap_config" {
  path = "ldap/config"
  
  data_json = jsonencode({
    # OpenLDAP connection settings
    url          = "ldap://openldap.ldap.svc.cluster.local:389"
    binddn       = "cn=admin,dc=example,dc=com"
    bindpass     = "admin_password"
    
    # OpenLDAP schema and attributes
    schema       = "openldap"  # NOT "ad"
    userattr     = "cn"        # OpenLDAP uses cn, not sAMAccountName
    userdn       = "ou=users,dc=example,dc=com"
    
    # TLS for OpenLDAP (optional)
    starttls     = false  # Unless OpenLDAP has TLS configured
    insecure_tls = false
  })
}

# Create dual-account static role for OpenLDAP
resource "vault_generic_endpoint" "ldap_dual_role" {
  path = "ldap/static-role/db-service-rotation"
  
  data_json = jsonencode({
    # Primary account (active)
    username          = "db-service-a"
    dn                = "cn=db-service-a,ou=users,dc=example,dc=com"
    
    # Secondary account (standby, rotated into during grace period)
    username_b        = "db-service-b"
    dn_b              = "cn=db-service-b,ou=users,dc=example,dc=com"
    
    # Rotation settings
    rotation_period   = "3600s"  # Hourly rotation
    grace_period      = "300s"   # 5-minute transition window
    dual_account_mode = true
  })
}
```

---

## 4.3 Dual-Account Rotation Explained

**What is dual-account (blue/green) rotation?**

Instead of immediately changing one account's password (which breaks apps mid-request), your plugin:
1. **Active Phase** — App uses account A, plugin rotates A's password
2. **Grace Period** — App can use EITHER A or B (credentials synced with both)
3. **Standby Phase** — App switches to B, plugin rotates B

**Comparison:**
```
Single-Account Rotation (Standard LDAP Plugin):
────────────────────────────────────────────
Time  Account  Action
──────────────────────────────────────────
0s    user-1   ✅ Active (using password v1)
30s   user-1   🔄 Password rotated to v2
30s   user-1   ❌ Old password (v1) no longer works
31s   user-1   ✅ Using new password v2
────────────────────────────────────────────

Dual-Account Rotation (Your Custom Plugin):
────────────────────────────────────────────
Time  Primary   Secondary  Action
──────────────────────────────────────────
0s    user-a    user-b     ✅ Active: user-a (v1)
30s   user-a    user-b     🔄 Rotate: user-b to v2
35s   user-a    user-b     ✅ Active: can use BOTH
                          (Grace period: both work)
36s   user-a    user-b     🔄 Rotate: user-a to v3
40s   user-a    user-b     ✅ Switch: user-b is now primary
60s   user-b    user-a     Repeat...
────────────────────────────────────────────
```

---

# 5. KEY DIFFERENCES: ACTIVE DIRECTORY vs OPENLDAP FOR VAULT

## 5.1 Configuration Differences

| **Aspect** | **Active Directory** | **OpenLDAP** |
|-----------|-------------------|------------|
| **Vault Schema** | `"ad"` | `"openldap"` |
| **Default userattr** | `sAMAccountName` | `cn` (common name) |
| **User Identifier** | `vault-demo` (short login) | `cn=vault-demo` (full DN reference) |
| **DN Format** | `CN=User,CN=Users,DC=domain,DC=local` | `cn=user,ou=users,dc=domain,dc=com` |
| **Bind DN** | `CN=Admin,CN=Users,DC=mydomain,DC=local` | `cn=admin,dc=example,dc=com` |
| **User Search Base** | `CN=Users,DC=mydomain,DC=local` | `ou=users,dc=example,dc=com` |
| **Password Attribute** | `unicodePwd` (encrypted) | `userPassword` (hashed) |
| **Object Class** | `user` | `inetOrgPerson` |
| **Default Connection Port** | 636 (LDAPS only) | 389 (LDAP) or 636 (LDAPS) |
| **TLS Mode** | **REQUIRED for password ops** | Optional (recommended) |
| **Password Policy** | AD Group Policy Objects | LDAP attribute constraints |
| **Connection Protocol** | LDAPS (SSL/TLS required) | LDAP or LDAPS |
| **User Search Filter** | `(&(objectClass=user)(sAMAccountName=*))` | `(&(objectClass=inetOrgPerson)(cn=*))` |

---

## 5.2 Example Configurations Side-by-Side

### Active Directory (Your Current Project)
```hcl
resource "vault_ldap_secret_backend" "ad" {
  path        = "ldap"
  schema      = "ad"
  url         = "ldaps://10.0.0.5:636"  # LDAPS required
  binddn      = "CN=Administrator,CN=Users,DC=mydomain,DC=local"
  bindpass    = "P@ssw0rd123!"
  userdn      = "CN=Users,DC=mydomain,DC=local"
  userattr    = "cn"  # Your project overrides default (sAMAccountName)
  insecure_tls = true
}
```

### OpenLDAP (Using Vault Standard Plugin)
```hcl
resource "vault_ldap_secret_backend" "openldap" {
  path        = "ldap"
  schema      = "openldap"
  url         = "ldap://openldap.ldap.svc.cluster.local:389"
  binddn      = "cn=admin,dc=example,dc=com"
  bindpass    = "admin_password"
  userdn      = "ou=users,dc=example,dc=com"
  userattr    = "cn"  # Standard for OpenLDAP
  
  # TLS optional for OpenLDAP
  # starttls = true
  # insecure_tls = false
}
```

### OpenLDAP (Using Your Custom Dual-Account Plugin)
```hcl
resource "vault_generic_endpoint" "plugin_register" {
  path = "sys/plugins/catalog/secret/ldap_dual_account"
  data_json = jsonencode({
    sha256  = "e71b4bec10963fe5f704d710f34be5a933330126799541fd1bd7b0e3536a8dad"
    command = "vault-plugin-secrets-openldap"
  })
}

resource "vault_mount" "ldap_dual" {
  path = "ldap"
  type = "ldap_dual_account"
}

resource "vault_generic_endpoint" "ldap_config" {
  path = "ldap/config"
  data_json = jsonencode({
    url      = "ldap://openldap.ldap.svc.cluster.local:389"
    binddn   = "cn=admin,dc=example,dc=com"
    bindpass = "admin_password"
    schema   = "openldap"
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

## 5.3 Password Attribute Differences

### Active Directory: `unicodePwd`
- **Format:** UTF-16LE encoded, enclosed in double quotes
- **Storage:** Encrypted by AD (always)
- **Modification:** Requires LDAPS and special encoding
- **Example Value:** `"P@ssw0rd123!"`

### OpenLDAP: `userPassword`
- **Format:** LDAP-compliant hash (e.g., `{SSHA}...`)
- **Storage:** Hashed by OpenLDAP (configurable)
- **Modification:** Can use plain LDAP or LDAPS
- **Example Value:** `{SSHA}gxQkfTfG0k9l8fV/2dYxgE+vQs1dxV==`

**Vault Handles These Automatically:**
```
✅ Vault detects schema type
✅ Automatically formats password correctly
✅ Handles encoding (UTF-16LE for AD, Base64 for OpenLDAP)
✅ You don't need to manually encode passwords
```

---

# SUMMARY TABLE: Quick Reference

| **Topic** | **OpenLDAP** | **Active Directory** |
|---------|-----------|------------------|
| **Kubernetes Deployment** | StatefulSet (osixia/openldap or bitnami/openldap) | Requires external Windows infra |
| **Vault Schema** | `"openldap"` | `"ad"` |
| **User Attribute** | `cn` | `sAMAccountName` (default) / `cn` (override) |
| **Bind DN** | `cn=admin,dc=example,dc=com` | `CN=Administrator,CN=Users,DC=mydomain,DC=local` |
| **User DN** | `ou=users,dc=example,dc=com` | `CN=Users,DC=mydomain,DC=local` |
| **Connection** | LDAP (389) or LDAPS (636) | LDAPS REQUIRED (636) |
| **Plugin Compatibility** | ✅ Works with standard plugin + your custom dual-account plugin | ✅ Works with standard plugin + your custom dual-account plugin |
| **Dual-Account Rotation** | ✅ Fully supported via custom plugin | ✅ Fully supported via custom plugin |
| **Helm Chart** | `bitnami/openldap` (recommended) | N/A (Windows-based) |
| **Best for EKS** | ✅ Native Kubernetes, easy HA, cost-effective | ⚠️ Requires separate Windows infra |

---

## CONCLUSION

Your project uses **Active Directory** with Vault's LDAP secrets engine and your custom dual-account plugin. However:

✅ **You can easily switch to OpenLDAP** by:
1. Deploying OpenLDAP to EKS (StatefulSet or Bitnami Helm chart)
2. Changing schema from `"ad"` to `"openldap"`
3. Changing userattr from default to `"cn"`
4. Updating DN formats (standard LDAP format vs AD format)
5. Your custom plugin works with OpenLDAP out of the box

✅ **OpenLDAP on EKS is production-ready:**
- Standard Linux nodes work fine
- Bitnami Helm chart provides enterprise features
- Persistent storage via EBS
- Full TLS/LDAPS support

✅ **Your custom plugin is backend-agnostic:**
- Dual-account rotation works with both AD and OpenLDAP
- Just change the configuration values
- Plugin binary remains the same

