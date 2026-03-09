# Research Documentation

This directory contains comprehensive research findings for the aws-vault-ldap-k8s project.

## Documents

### 1. **SUMMARY.md** ⭐ START HERE
Quick reference guide covering:
- OpenLDAP Docker images comparison
- Running OpenLDAP on EKS
- OpenLDAP + Vault LDAP Secrets Engine configuration
- Bitnami OpenLDAP Helm chart essentials
- Custom vault-plugin-secrets-openldap compatibility
- AD vs OpenLDAP configuration side-by-side
- Migration checklist from AD to OpenLDAP

**Read time:** 10-15 minutes

### 2. **openldap-vault-integration.md** 📚 DETAILED REFERENCE
Complete technical reference (31KB, 1103 lines) covering:
- **Section 1:** OpenLDAP on Kubernetes/EKS
  - osixia/openldap image details
  - bitnami/openldap Helm chart (full values reference)
  - Running OpenLDAP reliably on EKS
  - StatefulSet configuration example
  
- **Section 2:** OpenLDAP + Vault LDAP Secrets Engine
  - Schema comparison (openldap vs ad vs default)
  - Userattr configuration (cn vs sAMAccountName)
  - Bind DN and User DN formats
  - Static roles configuration
  - Complete Terraform examples
  
- **Section 3:** Bitnami OpenLDAP Helm Chart
  - Complete helm values reference (500+ lines)
  - Installation and verification steps
  
- **Section 4:** Custom Vault Plugin
  - vault-plugin-secrets-openldap overview
  - Dual-account (blue/green) rotation explained
  - Compatibility with OpenLDAP and AD
  
- **Section 5:** AD vs OpenLDAP
  - Configuration differences table
  - Example configurations side-by-side
  - Password attribute differences
  - Quick reference table

**Read time:** 45-60 minutes (or use as reference)

### 3. **findings.md**
Status of secret delivery methods implementation (VSO, Vault Agent, CSI Driver).

---

## Key Findings at a Glance

### Your Project's Current Setup
- **LDAP Backend:** Active Directory (Windows EC2, AD CS for LDAPS)
- **Vault Plugin:** Custom `vault-plugin-secrets-openldap` (dual-account rotation)
- **Configuration:** Schema=`"ad"`, LDAPS port 636, userattr=`"cn"` (overridden)

### Switching to OpenLDAP
✅ **Fully Supported** — Your plugin works with OpenLDAP out-of-the-box
- Change `schema` from `"ad"` to `"openldap"`
- Change `url` from `"ldaps://..."` to `"ldap://..."` or `"ldaps://..."`
- Change DN formats (standard LDAP format vs AD format)
- Everything else remains the same!

### OpenLDAP on EKS
✅ **Production-Ready**
- Use **Bitnami Helm chart** for enterprise features
- **StatefulSet** with **EBS persistent volumes** (gp3)
- Works perfectly with standard Linux nodes
- Resource requirements: 250m CPU, 256Mi RAM minimum
- Cost: Cheaper than Windows EC2 infrastructure

---

## Configuration Quick References

### OpenLDAP Schema (Vault)
```hcl
schema   = "openldap"
userattr = "cn"
userdn   = "ou=users,dc=example,dc=com"
binddn   = "cn=admin,dc=example,dc=com"
```

### AD Schema (Your Current Project)
```hcl
schema   = "ad"
userattr = "cn"  # You override default sAMAccountName
userdn   = "CN=Users,DC=mydomain,DC=local"
binddn   = "CN=Administrator,CN=Users,DC=mydomain,DC=local"
```

### Bitnami OpenLDAP Install
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install openldap bitnami/openldap \
  --namespace ldap --create-namespace \
  --set auth.adminPassword=changeme123! \
  --set persistence.enabled=true \
  --set persistence.size=8Gi \
  --set persistence.storageClass=gp3
```

---

## Related Documentation
- **Project README:** ../../README.md
- **Terraform Copilot Instructions:** ../../.github/copilot-instructions.md
- **Vault LDAP Plugin:** https://developer.hashicorp.com/vault/docs/secrets/ldap
- **Vault Secrets Operator:** https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso

---

## Contributors
- **Research Date:** 2025-01-14
- **Updated:** 2025-03-09

Last updated: $(date)
