# aws-vault-ldap-k8s

Vault demo with LDAP secrets engine and Kubernetes Secrets Operator - demonstrating automated password rotation for Active Directory accounts.

## Overview

This project demonstrates HashiCorp Vault's LDAP secrets engine integrated with Active Directory for automated password rotation, deployed on AWS EKS. Credentials are securely delivered to a Python web application using the Vault Secrets Operator (VSO).

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS VPC                                  │
│                                                                  │
│  ┌──────────────┐      ┌──────────────────────────────────┐    │
│  │              │      │                                   │    │
│  │  Active      │◄─────┤  Vault LDAP Secrets Engine       │    │
│  │  Directory   │      │  - Static Role                    │    │
│  │  (EC2)       │      │  - 24hr Password Rotation         │    │
│  │              │      │                                   │    │
│  └──────────────┘      └─────────────┬────────────────────┘    │
│                                      │                          │
│                                      ▼                          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │            EKS Cluster                                    │  │
│  │                                                           │  │
│  │  ┌──────────────────┐      ┌────────────────────────┐  │  │
│  │  │                  │      │                         │  │  │
│  │  │  Vault Secrets   │─────►│  Python Web App         │  │  │
│  │  │  Operator (VSO)  │      │  (LDAP Creds Display)   │  │  │
│  │  │                  │      │                         │  │  │
│  │  └──────────────────┘      └────────────────────────┘  │  │
│  │                                                           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────┐                                               │
│  │  Admin VM    │  (For accessing Vault & K8s)                 │
│  └──────────────┘                                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Features

- ✅ **LDAP Static Role**: Vault automatically rotates AD account passwords every 24 hours
- ✅ **Vault Secrets Operator**: Syncs rotated credentials from Vault to Kubernetes
- ✅ **Python Web App**: Displays live LDAP credentials with automatic updates
- ✅ **Infrastructure as Code**: Full Terraform Stacks implementation
- ✅ **AWS EKS**: Production-grade Kubernetes on AWS
- ✅ **Admin VM**: Bastion host for secure access

## Prerequisites

- **Terraform Stacks** (version with stacks support)
- **AWS Account** with appropriate permissions
- **AWS CLI** configured with credentials
- **HCP Terraform** account (for variable sets)
- **Vault Enterprise License** (for LDAP secrets engine)

## Project Structure

```
.
├── components.tfcomponent.hcl    # Stack component definitions
├── deployments.tfdeploy.hcl      # Deployment configurations
├── providers.tfcomponent.hcl     # Provider configurations
├── variables.tfcomponent.hcl     # Stack variables
├── modules/
│   ├── AWS_DC/                   # Active Directory setup
│   ├── admin_vm/                 # Admin bastion host
│   ├── kube0/                    # EKS cluster infrastructure
│   ├── kube1/                    # Vault cluster & VSO installation
│   ├── ldap_app/                    # LDAP app deployment
│   ├── vault/                    # Vault Helm chart deployment
│   └── vault_ldap_secrets/       # LDAP secrets engine config
└── python-app/                   # Python Flask application
```

## Quick Start

### 1. Configure Variable Sets in HCP Terraform

Create two variable sets:

**`aws_creds` (Category: env)**
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

**`vault_license` (Category: terraform)**
- `vault_license_key`

Update the varset IDs in `deployments.tfdeploy.hcl`.

### 2. Deploy the Stack

```bash
# Initialize Terraform Stacks
terraform init

# Plan the deployment
terraform plan -deployment=development

# Apply the deployment
terraform apply -deployment=development
```

### 3. Access the Demo

After deployment completes:

```bash
# Get outputs
terraform output -deployment=development

# Get LDAP app LoadBalancer URL
kubectl get svc ldap-credentials-app -n <namespace>

# Access the application
open http://<loadbalancer-url>
```

## Components

### 1. LDAP Secrets Engine (`vault_ldap_secrets`)

Configures Vault's LDAP secrets engine with:
- Connection to Active Directory
- Static role for password rotation
- Policy for credential access
- 24-hour rotation period (configurable)

**Module:** `modules/vault_ldap_secrets/`

### 2. Python Web Application (`python-app/`)

Flask application that displays LDAP credentials:
- Reads credentials from environment variables
- Displays username, password, DN
- Health check endpoint
- Auto-restart on credential rotation

**Docker Image:** `ghcr.io/andybaran/vault-ldap-demo:v1.0.0`

### 3. Vault Secrets Operator Integration (`ldap_app`)

VSO configuration for LDAP credentials:
- `VaultStaticSecret` CR syncs from Vault
- Kubernetes secret created automatically
- Environment variables injected into pods
- Rolling updates on credential rotation

**Module:** `modules/ldap_app/`

### 4. Infrastructure Components

- **`kube0`**: EKS cluster, VPC, networking
- **`kube1`**: Vault installation, VSO deployment
- **`vault_cluster`**: Vault Helm chart, initialization
- **`admin_vm`**: Bastion host for access
- **`ldap`**: Active Directory EC2 instance

## Validation Steps

### 1. Verify LDAP Secrets Engine

```bash
# SSH to admin VM
ssh -i <ssh-key> ubuntu@<admin-vm-ip>

# Access Vault (from admin VM)
export VAULT_ADDR=http://<vault-internal-lb>:8200
export VAULT_TOKEN=<root-token>

# Check LDAP mount
vault secrets list

# Read static role configuration
vault read ldap/static-role/demo-service-account

# Get credentials (triggers rotation if expired)
vault read ldap/static-cred/demo-service-account
```

### 2. Verify VSO Synchronization

```bash
# Check VaultStaticSecret status
kubectl get vaultstaticsecret -n <namespace>

# View synced Kubernetes secret
kubectl get secret ldap-credentials -n <namespace> -o yaml

# Check secret data (base64 encoded)
kubectl get secret ldap-credentials -n <namespace> -o jsonpath='{.data.username}' | base64 -d
```

### 3. Verify Python Application

```bash
# Check deployment status
kubectl get deployment ldap-credentials-app -n <namespace>

# Check pod logs
kubectl logs -l app=ldap-credentials-app -n <namespace>

# Get LoadBalancer URL
kubectl get svc ldap-credentials-app -n <namespace>

# Access the application
curl http://<loadbalancer-url>
```

### 4. Test Password Rotation

```bash
# Force immediate rotation
vault write -f ldap/rotate-role/demo-service-account

# Watch for pod restart (automatic via VSO)
kubectl get pods -l app=ldap-credentials-app -n <namespace> -w

# Verify new credentials in app UI
open http://<loadbalancer-url>
```

## Configuration

### Customize LDAP Static Role

Edit `modules/vault_ldap_secrets/variables.tf`:

```hcl
variable "static_role_rotation_period" {
  description = "Password rotation period in seconds"
  type        = number
  default     = 86400  # 24 hours
}

variable "static_role_username" {
  description = "AD username for the static role"
  type        = string
  default     = "vault-demo"
}
```

### Customize Python App

Modify deployment replicas in `modules/ldap_app/4_ldap_app.tf`:

```hcl
spec {
  replicas = 3  # Increase for HA
  ...
}
```

## Troubleshooting

### LDAP Connection Issues

```bash
# Check LDAP server connectivity
vault read ldap/config

# Test LDAP bind
ldapsearch -H ldap://<ldap-ip> -D "CN=Administrator,CN=Users,DC=mydomain,DC=local" -w <password>
```

### VSO Not Syncing Secrets

```bash
# Check VSO logs
kubectl logs -n vault-secrets-operator-system deployment/vault-secrets-operator-controller-manager

# Verify VaultAuth configuration
kubectl get vaultauth -n <namespace>

# Check VaultStaticSecret events
kubectl describe vaultstaticsecret ldap-credentials-app -n <namespace>
```

### Python App Not Starting

```bash
# Check pod status
kubectl describe pod -l app=ldap-credentials-app -n <namespace>

# View container logs
kubectl logs -l app=ldap-credentials-app -n <namespace>

# Verify secret exists
kubectl get secret ldap-credentials -n <namespace>
```

## Cleanup

```bash
# Destroy the entire stack
terraform destroy -deployment=development

# Confirm when prompted
```

## Security Considerations

This is a **DEMO PROJECT** and includes some simplified security configurations:

- ❌ Vault root token exposed in outputs (disable for production)
- ❌ TLS verification skipped for Vault (enable for production)
- ❌ LoadBalancer exposes app publicly (use Ingress + auth)
- ❌ Shared security groups (isolate per component)

**For Production:**
- Enable Vault TLS with proper certificates
- Use Vault namespaces and auth methods (not root token)
- Implement network policies and security groups
- Use private subnets with NAT gateways
- Enable audit logging and monitoring
- Rotate Vault root token and unseal keys

## References

- [HashiCorp Vault LDAP Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/ldap)
- [Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/platform/k8s/vso)
- [Terraform Stacks](https://developer.hashicorp.com/terraform/language/stacks)
- [AWS EKS](https://docs.aws.amazon.com/eks/)

## Contributing

This is a demo project. For questions or improvements, please open an issue on GitHub.

## License

This project is provided as-is for demonstration purposes.
