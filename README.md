# aws-vault-ldap-k8s

Vault demo with LDAP secrets engine and Active Directory password rotation — delivered to a live web application via three different secret delivery methods, all deployed on AWS EKS using **Terraform Stacks**.

## Overview

This project demonstrates HashiCorp Vault's LDAP secrets engine integrated with Active Directory for automated password rotation, deployed on AWS EKS using **Terraform Stacks**. Rotated credentials are delivered to a Python web application (v3.0.0) using three parallel delivery methods — Vault Secrets Operator (VSO), Vault Agent sidecar, and Vault CSI Driver — each running as a separate Kubernetes Deployment.

In **dual-account mode** (default), Vault uses a custom blue/green rotation plugin that keeps two AD accounts in a rotation cycle with a configurable grace period, ensuring zero-downtime credential handoff.

### Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          AWS VPC (us-east-2)                              │
│                                                                            │
│  ┌────────────────────┐    ┌──────────────────────────────────────────┐  │
│  │  Active Directory   │◄───┤  Vault LDAP Secrets Engine (dual-acct)   │  │
│  │  Domain Controller  │    │  - dual-rotation-demo   (svc-rotate-a/b) │  │
│  │  (Windows Server    │    │  - vault-agent-dual-role(svc-rotate-c/d) │  │
│  │   2025, mydomain)   │    │  - csi-dual-role        (svc-rotate-e/f) │  │
│  └────────────────────┘    └────────────────┬─────────────────────────┘  │
│                                              │                             │
│  ┌───────────────────────────────────────────▼────────────────────────┐  │
│  │                         EKS Cluster                                  │  │
│  │                                                                       │  │
│  │  ┌──────────────┐  ┌───────────────┐  ┌────────────────────────┐   │  │
│  │  │ Vault HA     │  │ VSO v0.9.0    │  │ Python App (VSO)       │   │  │
│  │  │ (3-node Raft)│─►│ VaultDynamic  │─►│ SECRET_DELIVERY_METHOD │   │  │
│  │  │              │  │ Secret CR     │  │ =vault-secrets-operator│   │  │
│  │  │              │  └───────────────┘  └────────────────────────┘   │  │
│  │  │              │                                                    │  │
│  │  │              │  ┌───────────────┐  ┌────────────────────────┐   │  │
│  │  │              │─►│ Vault Agent   │─►│ Python App (Agent)     │   │  │
│  │  │              │  │ Sidecar       │  │ SECRET_DELIVERY_METHOD │   │  │
│  │  │              │  │ (init+sidecar)│  │ =vault-agent-sidecar   │   │  │
│  │  │              │  └───────────────┘  └────────────────────────┘   │  │
│  │  │              │                                                    │  │
│  │  │              │  ┌───────────────┐  ┌────────────────────────┐   │  │
│  │  │              │─►│ CSI Driver    │─►│ Python App (CSI)       │   │  │
│  │  │              │  │ SecretProvider│  │ SECRET_DELIVERY_METHOD │   │  │
│  │  └──────────────┘  │ Class         │  │ =vault-csi-driver      │   │  │
│  │                    └───────────────┘  └────────────────────────┘   │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘
```

### Key Features

- ✅ **Dual-Account Rotation** — Custom blue/green Vault plugin rotates between two AD accounts with a configurable grace period
- ✅ **Three Secret Delivery Methods** — VSO, Vault Agent sidecar, and Vault CSI Driver running side-by-side
- ✅ **Direct Vault Polling** — Python app (v3.0.0) uses the `hvac` library to read live rotation state from Vault
- ✅ **Timeline UI** — HDS-styled UI with Account A/B rotation phases (Active/Grace/Inactive) and live countdown timer
- ✅ **Terraform Stacks** — Full infrastructure-as-code with component dependency graph
- ✅ **AWS EKS** — HA Kubernetes cluster (K8s 1.34), 3 Linux nodes, EBS CSI driver
- ✅ **Active Directory** — Windows Server 2025 DC with AD CS for LDAPS

## Prerequisites

- **Terraform** ≥ 1.14 (stacks-enabled)
- **HCP Terraform** account with Stacks access
- **AWS Account** with appropriate permissions
- **Vault Enterprise License** (required for the LDAP secrets engine)

## Project Structure

```
.
├── components.tfcomponent.hcl    # Stack component definitions & wiring
├── deployments.tfdeploy.hcl      # Deployment config (region, varsets, inputs)
├── providers.tfcomponent.hcl     # Provider definitions with pinned versions
├── variables.tfcomponent.hcl     # Stack-level variable declarations
├── modules/
│   ├── AWS_DC/                   # Active Directory domain controller (Windows Server 2025 EC2)
│   ├── kube0/                    # VPC, EKS cluster, security groups
│   ├── kube1/                    # Nginx ingress, Vault ServiceAccount, license secret
│   ├── vault/                    # Vault Helm chart (HA Raft), init job, VSO, CSI driver
│   ├── vault_ldap_secrets/       # LDAP secrets engine, dual-account roles, K8s auth
│   └── ldap_app/                 # Three app deployments (VSO, Vault Agent, CSI)
└── python-app/                   # Flask web application (Docker image)
```

## Component Dependency Graph

```
kube0 (VPC, EKS, security groups)
  ├──► kube1 (nginx ingress, vault SA, vault license secret)
  │      └──► vault_cluster (Vault Helm HA Raft, init job, VSO, CSI Driver)
  │             ├──► vault_ldap_secrets (LDAP engine, 3 dual-account static roles, K8s auth)
  │             │      └──► ldap_app (VSO deployment, Vault Agent deployment, CSI deployment)
  │             └──► [vault provider: var.vault_address + var.vault_token from varset]
  └──► ldap (Windows Server 2025 DC, AD forest mydomain.local, AD CS for LDAPS)
         └──► vault_ldap_secrets (receives static_roles map with test account credentials)
```

## Quick Start

### 1. Configure Variable Sets in HCP Terraform

Create two variable sets and reference them in `deployments.tfdeploy.hcl`:

**`aws_creds` (Category: env)**
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

**`vault_license` (Category: terraform)**
- `vault_license_key`
- `vault_address` — Vault API LoadBalancer URL (update after first apply)
- `vault_token` — Vault root token (update after first apply)

### 2. Deploy the Stack

```bash
# Via HCP Terraform (triggered by push to main)
git push origin main

# Or manually from the CLI
terraform init
terraform plan -deployment=development
terraform apply -deployment=development
```

> **Note:** The first deployment creates ~83 resources and may take 20–30 minutes. Components that depend on not-yet-created infrastructure defer and resolve in subsequent runs.

### 3. Access the Demo

```bash
# Configure kubectl (output from stack)
aws eks update-kubeconfig --name <cluster-name> --region us-east-2

# Get app URLs from stack outputs
terraform output ldap_app_access_info         # VSO delivery
terraform output ldap_app_vault_agent_url     # Vault Agent delivery
terraform output ldap_app_csi_url             # CSI Driver delivery
```

Each app URL displays:
- **Active account** username and password
- **Standby account** (during grace period)
- **Rotation period**, **grace period**, and **live countdown timer**
- **Delivery method badge** (VSO / Vault Agent / CSI)
- **Timeline visualization** — Account A/B rotation phases color-coded (Active=blue, Grace=yellow, Inactive=red)

## Components

### Active Directory (`AWS_DC`)

Windows Server 2025 EC2 Domain Controller:
- Two-boot provisioning: first boot promotes to DC, second boot installs AD CS and creates test accounts
- AD forest `mydomain.local` (NetBIOS: `mydomain`)
- AD CS Enterprise Root CA enables LDAPS on port 636
- 8 test service accounts: `svc-rotate-a` through `svc-rotate-f`, `svc-single`, `svc-lib`
- SSM access for remote diagnostics (no bastion required)

### Vault LDAP Secrets Engine (`vault_ldap_secrets`)

In dual-account mode (default):
- Custom `ldap_dual_account` plugin at `sys/plugins/catalog/secret/ldap_dual_account`
- 3 dual-account static roles (100s rotation, 20s grace period):

| Role | Accounts | Delivery |
|------|----------|----------|
| `dual-rotation-demo` | svc-rotate-a / svc-rotate-b | VSO |
| `vault-agent-dual-role` | svc-rotate-c / svc-rotate-d | Vault Agent |
| `csi-dual-role` | svc-rotate-e / svc-rotate-f | CSI Driver |

- Kubernetes auth backend at path `kubernetes` with 4 roles (`vso-role`, `ldap-app-role`, `vault-agent-app-role`, `csi-app-role`)

### Python Web Application (`python-app/`)

Flask application v3.0.0 supporting three delivery modes:

| `SECRET_DELIVERY_METHOD` | Source | Auth |
|--------------------------|--------|------|
| `vault-secrets-operator` | K8s Secret (VSO-managed) + direct Vault polling | `ldap-app-role` SA token |
| `vault-agent-sidecar` | File rendered by Vault Agent at `/vault/secrets/ldap-creds` | Projected SA token (`vault-agent-app-role`) |
| `vault-csi-driver` | Files mounted by CSI Driver at `/vault/secrets/` | Projected SA token (`csi-app-role`) |

**Docker Image:** `ghcr.io/andybaran/vault-ldap-demo:latest`

### Infrastructure Components

| Component | Module | Purpose |
|-----------|--------|---------|
| `kube0` | `modules/kube0/` | VPC (10.0.0.0/16), EKS (K8s 1.34), EBS CSI driver, security groups |
| `kube1` | `modules/kube1/` | Nginx ingress, Vault ServiceAccount, Vault license secret |
| `vault_cluster` | `modules/vault/` | Vault Enterprise HA (3-node Raft), init job, VSO v0.9.0, CSI Driver v1.4.7 |
| `ldap` | `modules/AWS_DC/` | Windows Server 2025 DC, AD forest, AD CS for LDAPS |
| `vault_ldap_secrets` | `modules/vault_ldap_secrets/` | LDAP secrets engine, dual-account static roles, K8s auth |
| `ldap_app` | `modules/ldap_app/` | Three app deployments (VSO, Vault Agent sidecar, CSI Driver) |

## Validation

### Verify LDAP Secrets Engine

```bash
export VAULT_ADDR=http://<vault-lb>:8200
export VAULT_TOKEN=<root-token>

# List mounts
vault secrets list

# Read dual-account role config
vault read ldap/static-role/dual-rotation-demo

# Read live credentials
vault read ldap/static-cred/dual-rotation-demo
```

### Verify VSO Synchronization

```bash
# Check VaultDynamicSecret status
kubectl get vaultdynamicsecret -n default

# View synced secret
kubectl get secret ldap-credentials -n default -o jsonpath='{.data.active_account}' | base64 -d

# Check VSO logs
kubectl logs deployment/vault-secrets-operator-controller-manager -n default -c manager --tail=20
```

### Verify All Three Apps

```bash
# Check all app pods
kubectl get pods -n default

# Get all service URLs
kubectl get svc -n default | grep ldap

# Test credential rotation (VSO app)
curl -s http://<vso-lb>/api/credentials | jq .
```

## Configuration

### Key Deployment Values (`deployments.tfdeploy.hcl`)

| Parameter | Value |
|-----------|-------|
| Region | `us-east-2` |
| Customer name | `fidelity` |
| Instance type | `c5.xlarge` |
| EKS AMI | `1.34.2-20260128` |
| Rotation period | `100s` |
| Grace period | `20s` |
| Dual-account mode | `true` |

### Provider Versions (`providers.tfcomponent.hcl`)

| Provider | Version |
|----------|---------|
| aws | 6.27.0 |
| vault | 5.6.0 |
| kubernetes | 3.0.1 |
| helm | 3.1.1 |
| tls | ~> 4.0.5 |
| random | ~> 3.6.0 |
| http | ~> 3.5.0 |
| cloudinit | 2.3.7 |
| null | 3.2.4 |
| time | 0.13.1 |

## Stack Outputs

| Output | Description |
|--------|-------------|
| `public-dns-address` | DC Elastic IP public DNS |
| `ldap-eip-public-ip` | DC Elastic IP |
| `ldap-private-ip` | DC private IP |
| `password` | DC Administrator password |
| `eks_cluster_name` | `aws eks update-kubeconfig` command |
| `vault_service_name` | `"vault"` |
| `vault_loadbalancer_hostname` | Vault API LB URL |
| `vault_ui_loadbalancer_hostname` | Vault UI LB URL |
| `vault_root_token` | Vault root token |
| `vault_ldap_secrets_path` | LDAP secrets mount path |
| `ldap_app_access_info` | VSO app URL |
| `ldap_app_vault_agent_url` | Vault Agent app URL |
| `ldap_app_csi_url` | CSI Driver app URL |

## CI/CD

| Workflow | Trigger | Image |
|----------|---------|-------|
| `build-python-app-image.yml` | Push to `main` on `python-app/**` | `ghcr.io/andybaran/vault-ldap-demo` |

## Security Considerations

This is a **demo project** with simplified security:

- ⚠️ Vault root token exposed in outputs (use auth methods in production)
- ⚠️ TLS verification skipped (`insecure_tls=true`, `skipTLSVerify=true`)
- ⚠️ LoadBalancers are internet-facing (use private LBs + VPN in production)
- ⚠️ All resources in `default` namespace
- ⚠️ DC in public subnet with Elastic IP

## Troubleshooting

### VSO Not Syncing

```bash
kubectl logs deployment/vault-secrets-operator-controller-manager -n default -c manager
kubectl describe vaultdynamicsecret ldap-credentials-app -n default
kubectl get vaultauth default -n default -o yaml
```

Common causes: missing `allowStaticCreds: true`, VaultAuth role mismatch, stale Vault token in varset.

### Vault Init Failed

```bash
kubectl logs job/vault-init -n default
kubectl get secret vault-init-data -n default -o jsonpath='{.data.init\.json}' | base64 -d | jq .
```

### DC / LDAP Issues

```bash
# Verify AD CS is running and LDAPS is available
# From an EKS pod with ldap tools:
ldapsearch -H ldaps://<dc-priv-ip> -x -D "CN=Administrator,CN=Users,DC=mydomain,DC=local" -w <password> -b "CN=Users,DC=mydomain,DC=local" "(cn=svc-rotate-a)"
```

### Pod Startup Issues

```bash
kubectl describe pod -l app=ldap-credentials-app -n default
kubectl logs -l app=ldap-credentials-app -n default
```

## References

- [Vault LDAP Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/ldap)
- [Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso)
- [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/)
- [Vault Agent Injector](https://developer.hashicorp.com/vault/docs/platform/k8s/injector)
- [Terraform Stacks](https://developer.hashicorp.com/terraform/language/stacks)
- [AWS EKS](https://docs.aws.amazon.com/eks/)

## Contributing

For questions or improvements, please open an issue on GitHub.

## License

This project is provided as-is for demonstration purposes.

## Overview

This project demonstrates HashiCorp Vault's LDAP secrets engine integrated with Active Directory for automated password rotation, deployed on AWS EKS using **Terraform Stacks**. Rotated credentials are securely delivered to a Python web application using the **Vault Secrets Operator (VSO)**, which syncs them into Kubernetes secrets every few seconds.

### Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                          AWS VPC (us-east-2)                     │
│                                                                  │
│  ┌──────────────────┐    ┌──────────────────────────────────┐   │
│  │  Active Directory │◄───┤  Vault LDAP Secrets Engine       │   │
│  │  Domain Controller│    │  - Static Role: vault-demo       │   │
│  │  (Windows EC2)    │    │  - 30s Password Rotation         │   │
│  │  mydomain.local   │    │  - LDAPS via AD CS               │   │
│  └──────────────────┘    └──────────────┬───────────────────┘   │
│                                         │                        │
│                                         ▼                        │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    EKS Cluster                             │  │
│  │                                                            │  │
│  │  ┌─────────────┐   ┌──────────────┐   ┌──────────────┐  │  │
│  │  │ Vault HA    │   │ Vault Secrets│   │ Python Web   │  │  │
│  │  │ (3 nodes,   │──►│ Operator     │──►│ App (2       │  │  │
│  │  │  Raft)      │   │ (VSO v0.9)   │   │ replicas)    │  │  │
│  │  └─────────────┘   └──────────────┘   └──────────────┘  │  │
│  │                                                            │  │
│  └───────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

### Key Features

- ✅ **LDAP Static Role** — Vault rotates the AD `vault-demo` account password every 30 seconds
- ✅ **Vault Secrets Operator** — Syncs rotated credentials from Vault to a Kubernetes secret using `VaultDynamicSecret` with `allowStaticCreds`
- ✅ **Python Web App** — HDS-styled UI with live countdown timer and refresh button
- ✅ **Terraform Stacks** — Full infrastructure-as-code with component dependency graph
- ✅ **AWS EKS** — HA Kubernetes cluster with Linux and Windows node groups
- ✅ **Active Directory** — Windows Server 2022 DC with AD CS for LDAPS

## Prerequisites

- **Terraform** ≥ 1.14 (stacks-enabled)
- **HCP Terraform** account with Stacks access
- **AWS Account** with appropriate permissions
- **Vault Enterprise License** (required for the LDAP secrets engine)

## Project Structure

```
.
├── components.tfcomponent.hcl    # Stack component definitions & wiring
├── deployments.tfdeploy.hcl      # Deployment config (region, varsets, inputs)
├── providers.tfcomponent.hcl     # Provider definitions with pinned versions
├── variables.tfcomponent.hcl     # Stack-level variable declarations
├── modules/
│   ├── AWS_DC/                   # Active Directory domain controller (Windows EC2)
│   ├── kube0/                    # VPC, EKS cluster, security groups
│   ├── kube1/                    # Nginx ingress, Vault ServiceAccount, license secret
│   ├── vault/                    # Vault Helm chart (HA Raft), init job, VSO
│   ├── vault_ldap_secrets/       # LDAP secrets engine, static role, K8s auth
│   ├── ldap_app/                 # VaultDynamicSecret CR, app deployment, service
│   └── windows_config/           # Windows IPAM, AD user creation job
├── python-app/                   # Flask web application (Docker image)
└── docker/
    └── ad-tools/                 # Windows container for AD user management
```

## Component Dependency Graph

```
kube0 (VPC, EKS, security groups)
  ├──► kube1 (nginx ingress, vault SA, vault license secret)
  │      └──► vault_cluster (Vault Helm, init job, VSO, VaultConnection, VaultAuth)
  │             ├──► vault_ldap_secrets (LDAP engine, static role, K8s auth backend)
  │             │      └──► ldap_app (VaultDynamicSecret CR, Deployment, Service)
  │             └──► [vault provider configured from vault_cluster outputs]
  ├──► ldap (Windows EC2 domain controller, AD forest, AD CS for LDAPS)
  │      └──► windows_config (Windows IPAM, create vault-demo AD user via K8s job)
  │             └──► vault_ldap_secrets (depends on ad_user_job_completed)
  └──► windows_config (uses kube0 + kube1 + ldap outputs)
```

## Quick Start

### 1. Configure Variable Sets in HCP Terraform

Create two variable sets and update the IDs in `deployments.tfdeploy.hcl`:

**`aws_creds` (Category: env)**
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`
- `AWS_SESSION_EXPIRATION`

**`vault_license` (Category: terraform)**
- `vault_license_key`

### 2. Deploy the Stack

The stack deploys via HCP Terraform when changes are pushed to the `main` branch. The VCS connection triggers a plan automatically.

```bash
# Manual deployment (from the CLI)
terraform init
terraform plan -deployment=development
terraform apply -deployment=development
```

> **Note:** The first deployment creates ~83 resources and may take 20-30 minutes. Deferred resources (components that depend on not-yet-created infrastructure) resolve in subsequent runs.

### 3. Access the Demo

```bash
# Configure kubectl
aws eks update-kubeconfig --name <cluster-name> --region us-east-2

# Get the LDAP app URL
kubectl get svc ldap-credentials-app -n default \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Open in browser
open http://<loadbalancer-hostname>
```

The web app displays:
- **Username** — the AD account managed by Vault
- **Password** — the current rotated password
- **Last Vault Rotation** — timestamp of the most recent rotation
- **Countdown timer** — seconds until the next rotation
- **Refresh button** — appears 5 seconds after the countdown reaches zero

## Components

### Vault LDAP Secrets Engine (`vault_ldap_secrets`)

Configures Vault's LDAP secrets engine with:
- LDAPS connection to Active Directory (`ldaps://<DC_IP>`, `insecure_tls=true`)
- Static role `demo-service-account` for the `vault-demo` AD user
- 30-second rotation period (configurable via `static_role_rotation_period`)
- `ldap-static-read` policy for credential access
- Kubernetes auth backend with role `vso-role` bound to `vso-auth` ServiceAccount

**Module:** `modules/vault_ldap_secrets/`

### Python Web Application (`python-app/`)

Flask application that displays LDAP credentials:
- Reads credentials from environment variables injected by VSO
- HDS-styled UI with live countdown timer and progress bar
- Refresh button appears 5 seconds after the countdown expires
- Health check endpoint at `/health` for K8s probes
- Rolling restart triggered by VSO on credential rotation

**Docker Image:** `ghcr.io/andybaran/vault-ldap-demo:latest`

### Vault Secrets Operator Integration (`ldap_app`)

VSO configuration using a `VaultDynamicSecret` CR:
- `allowStaticCreds: true` — enables syncing of LDAP static credentials
- `refreshAfter` — derived from rotation period (80%) for timely sync
- Kubernetes secret `ldap-credentials` created and updated automatically
- Environment variables (`LDAP_USERNAME`, `LDAP_PASSWORD`, `ROTATION_PERIOD`, etc.) injected into pods
- `rolloutRestartTargets` triggers pod rolling restart on secret change

**Module:** `modules/ldap_app/`

### Infrastructure Components

| Component | Module | Purpose |
|-----------|--------|---------|
| `kube0` | `modules/kube0/` | VPC (10.0.0.0/16), EKS cluster (K8s 1.34), Linux + Windows node groups |
| `kube1` | `modules/kube1/` | Nginx ingress controller, Vault ServiceAccount, license secret |
| `vault_cluster` | `modules/vault/` | Vault Enterprise HA (3-node Raft), init job, VSO v0.9.0 |
| `ldap` | `modules/AWS_DC/` | Windows Server 2022 DC, AD forest (`mydomain.local`), AD CS for LDAPS |
| `windows_config` | `modules/windows_config/` | Windows IPAM enablement, `vault-demo` AD user creation via K8s job |

## Validation

### Verify LDAP Secrets Engine

```bash
export VAULT_ADDR=http://<vault-lb>:8200
export VAULT_TOKEN=<root-token>

# Check LDAP mount
vault secrets list

# Read static role config
vault read ldap/static-role/demo-service-account

# Get current credentials
vault read ldap/static-cred/demo-service-account
```

### Verify VSO Synchronization

```bash
# Check VaultDynamicSecret status
kubectl get vaultdynamicsecret -n default

# View synced secret
kubectl get secret ldap-credentials -n default -o jsonpath='{.data.password}' | base64 -d

# Check VSO logs
kubectl logs deployment/vault-secrets-operator-controller-manager -n default -c manager --tail=20
```

### Verify the Application

```bash
# Check pods
kubectl get pods -l app=ldap-credentials-app -n default

# Get LoadBalancer URL
kubectl get svc ldap-credentials-app -n default

# Test credential rotation (check twice, 35s apart)
curl -s http://<lb-url> | grep credential-value
sleep 35
curl -s http://<lb-url> | grep credential-value
```

## Configuration

### Rotation Period

The rotation period is set in `components.tfcomponent.hcl`:

```hcl
# In the vault_ldap_secrets component
static_role_rotation_period = 30

# In the ldap_app component
static_role_rotation_period = 30
```

The VSO `refreshAfter` interval automatically derives from this value (80% of the rotation period).

### Provider Versions

All providers are pinned in `providers.tfcomponent.hcl`:

| Provider | Version |
|----------|---------|
| aws | 6.27.0 |
| vault | 5.6.0 |
| kubernetes | 3.0.1 |
| helm | 3.1.1 |
| tls | ~> 4.0.5 |
| random | ~> 3.6.0 |
| cloudinit | 2.3.7 |

## CI/CD

Docker images are built automatically by GitHub Actions on push to `main`:

| Workflow | Trigger | Image |
|----------|---------|-------|
| `build-python-app-image.yml` | `python-app/**` changes | `ghcr.io/andybaran/vault-ldap-demo` |
| `build-ad-tools-image.yml` | `docker/ad-tools/**` changes | `ghcr.io/andybaran/aws-vault-ldap-k8s/ad-tools` |

## Security Considerations

This is a **demo project** with simplified security for clarity:

- ⚠️ Vault root token exposed in outputs (use auth methods in production)
- ⚠️ TLS verification skipped for Vault (`insecure_tls=true`)
- ⚠️ LoadBalancer exposes app publicly (use Ingress + authentication)
- ⚠️ All resources in `default` namespace (use dedicated namespaces)
- ⚠️ DC in public subnet with EIP (use private subnets + VPN)

## Troubleshooting

### VSO Not Syncing Credentials

```bash
# Check VSO controller logs for errors
kubectl logs deployment/vault-secrets-operator-controller-manager -n default -c manager

# Verify VaultAuth is configured
kubectl get vaultauth -n default -o yaml

# Check VaultDynamicSecret events
kubectl describe vaultdynamicsecret ldap-credentials-app -n default
```

Common issues:
- Missing `allowStaticCreds: true` — required for LDAP static credentials
- Missing `refreshAfter` — required since static creds have no lease TTL
- VaultAuth role mismatch — ensure `vso-role` is configured in Vault's K8s auth

### LDAP Connection Issues

```bash
# Check connectivity from Vault to DC
vault read ldap/config

# Verify AD user exists
# (from a Windows node or the DC itself)
Get-ADUser vault-demo
```

### Pod Issues

```bash
kubectl describe pod -l app=ldap-credentials-app -n default
kubectl logs -l app=ldap-credentials-app -n default
kubectl get secret ldap-credentials -n default -o json | jq '.data | map_values(@base64d)'
```

## References

- [Vault LDAP Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/ldap)
- [Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso)
- [VSO API Reference — VaultDynamicSecret](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/api-reference#vaultdynamicsecret)
- [Terraform Stacks](https://developer.hashicorp.com/terraform/language/stacks)
- [AWS EKS](https://docs.aws.amazon.com/eks/)

## Contributing

For questions or improvements, please open an issue on GitHub.

## License

This project is provided as-is for demonstration purposes.
