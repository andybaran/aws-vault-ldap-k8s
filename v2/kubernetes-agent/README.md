# Kubernetes Agent Documentation

## Implementation Summary

Validated Kubernetes resource configurations for all three secret delivery methods.

## Resources by Delivery Method

### VSO (Vault Secrets Operator)

| Resource | Name | Purpose |
|----------|------|---------|
| VaultDynamicSecret | `ldap-credentials-app` | Syncs LDAP creds to K8s Secret |
| Secret | `ldap-credentials` | Created by VSO, mounted as env vars |
| Deployment | `ldap-credentials-app` | 2 replicas, uses env vars |
| Service | `ldap-credentials-app` | LoadBalancer on port 80 |

### Vault Agent Sidecar

| Resource | Name | Purpose |
|----------|------|---------|
| ServiceAccount | `ldap-app-vault-agent` | K8s auth identity |
| ConfigMap | `vault-agent-config` | Agent HCL configuration |
| Deployment | `ldap-app-vault-agent` | Init + sidecar + app containers |
| Service | `ldap-app-vault-agent` | LoadBalancer on port 80 |

### CSI Driver

| Resource | Name | Purpose |
|----------|------|---------|
| ServiceAccount | `ldap-app-csi` | K8s auth identity |
| SecretProviderClass | `ldap-csi-credentials` | Vault CSI provider config |
| Deployment | `ldap-app-csi` | App with CSI volume mount |
| Service | `ldap-app-csi` | LoadBalancer on port 80 |

## Verification Commands

```bash
# Check all deployments
kubectl get deployments -l 'app in (ldap-credentials-app, ldap-app-vault-agent, ldap-app-csi)'

# Check services and external IPs
kubectl get svc -l 'app in (ldap-credentials-app, ldap-app-vault-agent, ldap-app-csi)'

# Verify CSI SecretProviderClass
kubectl get secretproviderclass ldap-csi-credentials -o yaml

# Verify VaultDynamicSecret
kubectl get vaultdynamicsecret ldap-credentials-app -o yaml
```
