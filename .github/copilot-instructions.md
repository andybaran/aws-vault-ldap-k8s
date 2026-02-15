---
applyTo: "*.tf,*.hcl,*.md"
---

# Project: aws-vault-ldap-k8s

## Goal

Create an infrastructure-as-code demo using Terraform Stacks, AWS, EKS, and Vault with LDAP (Active Directory) integration. Demonstrates Vault configured with static roles that manage password rotation of an AD account. Rotated credentials are delivered to a Python web application via Vault Secrets Operator (VSO) deployed on EKS. The Python app displays the secrets on a webpage with a live countdown timer.

The code currently utilizes **Terraform Stacks** and all work must continue to do so.

## Guidelines

- Follow Terraform and HCL best practices for formatting and structuring code.
- Code should be clear, concise, and maintainable.
- Use comments to explain complex logic or decisions in the code.
- While security is important, avoid overcomplicating the code with excessive security measures that may hinder readability or maintainability. This is a demo project not meant for production use.
- When suggesting changes, ensure they align with the project's goals and existing architecture.
- Provide explanations for your code suggestions to help understand the reasoning behind them.
- Do research to ensure the latest and most efficient methods are used in the code. Particularly in regards to AWS services, Terraform providers, Terraform Modules and Terraform Stacks.
- When there is conflicting information regarding best practices or implementation details, prioritize official documentation skills and plugins from HashiCorp and AWS, including the local Terraform MCP server.
- Ask me clarifying questions one by one and wait for me to answer before asking another.
- Use the model Claude Opus 4.5 when generating code for this project.
- Do not commit directly to the main branch.
- I have set the correct environment variables to log into AWS.
- If you need credentials, prompt me for them and wait for my answer.

## Workflow

- **Do NOT start with a thorough code review** — this file contains a complete snapshot of the codebase architecture, modules, dependencies, and key implementation details. Use it as your starting context.
- Create a TODO list and then open a GitHub issue for each item on the list.
- When you are ready to work on an issue create a branch in which to do so.
- Working in parallel on multiple issues is preferred; if there are similar TODO's or GitHub issues, group them and work them in parallel.
- When you are done working on an issue make a PR to the main branch and close the issue.
- If subsequent issues depend on the issue you just closed, notify me and wait for me to approve a merge to the main branch.

## Maintaining This Document

**IMPORTANT:** When creating PRs, update the "Codebase Snapshot" section below to reflect any changes you made. This keeps future sessions from needing to re-read the entire codebase. Specifically update:
- File lists if files were added, removed, or renamed
- Module descriptions if behavior or interfaces changed
- Provider versions if bumped
- Dependency graph if component wiring changed
- Any new outputs, variables, or resources relevant to understanding the architecture

---

## Codebase Snapshot (last updated: 2026-02-15, post PR #151)

### Repository

- **GitHub:** `andybaran/aws-vault-ldap-k8s`
- **Default branch:** `main`, active development on `develop`
- **Terraform version:** 1.14.2 (stacks-enabled)

### Stack-Level Files (root)

| File | Purpose |
|------|---------|
| `components.tfcomponent.hcl` | Defines 6 stack components, their inputs/outputs, provider bindings, and dependency wiring |
| `deployments.tfdeploy.hcl` | Single `development` deployment targeting `us-east-2`, references HCP Terraform varsets `varset-oUu39eyQUoDbmxE1` (aws_creds) and `varset-fMrcJCnqUd6q4D9C` (vault_license) |
| `providers.tfcomponent.hcl` | All provider definitions with pinned versions |
| `variables.tfcomponent.hcl` | Stack-level variable declarations (region, customer_name, AWS creds as ephemeral, vault_license_key, eks_node_ami_release_version, allowlist_ip, vault_image_repository, vault_image_tag, ldap_app_image) |

### Provider Versions (pinned in `providers.tfcomponent.hcl`)

| Provider | Version |
|----------|---------|
| hashicorp/aws | 6.27.0 |
| hashicorp/vault | 5.6.0 |
| hashicorp/kubernetes | 3.0.1 |
| hashicorp/helm | 3.1.1 |
| hashicorp/tls | ~> 4.0.5 |
| hashicorp/random | ~> 3.6.0 |
| hashicorp/http | ~> 3.5.0 |
| hashicorp/cloudinit | 2.3.7 |
| hashicorp/null | 3.2.4 |
| hashicorp/time | 0.13.1 |

### Component Dependency Graph

```
kube0 (VPC, EKS, security groups)
  ├──► kube1 (nginx ingress, vault SA, vault license secret)
  │      └──► vault_cluster (Vault Helm HA Raft, init job, VSO, VaultConnection, VaultAuth)
  │             ├──► vault_ldap_secrets (LDAP engine, static role, K8s auth backend)
  │             │      └──► ldap_app (VaultDynamicSecret CR, Deployment, Service)
  │             └──► [vault provider configured from vault_cluster outputs]
  ├──► ldap (Windows EC2 domain controller, AD forest, AD CS for LDAPS)
  │      └──► windows_config (Windows IPAM, create vault-demo AD user via K8s job)
  │             └──► vault_ldap_secrets (depends on ad_user_job_completed)
  └──► windows_config (uses kube0 + kube1 + ldap outputs)
```

### Module Details

#### `modules/kube0/` — VPC, EKS Cluster, Security Groups
**Providers:** aws, random, tls, null, time, cloudinit

**Files:**
- `1_locals.tf` — Naming locals (`customer_id`, `demo_id`, `resources_prefix`), AZ selection (filters AZs supporting the requested instance type, picks up to 3), `random_string.identifier`
- `1_aws_network.tf` — VPC module (`terraform-aws-modules/vpc/aws` v6.5.1), CIDR `10.0.0.0/16`, single NAT gateway, public/private subnets with ELB tags
- `1_aws_eks.tf` — EKS module (`terraform-aws-modules/eks/aws` v21.11.0), K8s 1.34, public endpoint, `enable_cluster_creator_admin_permissions=true`, addons (coredns, eks-pod-identity-agent, kube-proxy, vpc-cni, aws-ebs-csi-driver), two managed node groups: `linux_nodes` (1-3, desired 3) and `windows_nodes` (ami_type `WINDOWS_CORE_2022_x86_64`, t3.large, 1-2, desired 1, tainted `os=windows:NoSchedule`). EBS CSI driver IAM role with IRSA.
- `2_security_groups.tf` — `shared_internal` SG: allows all inbound from VPC CIDR, all outbound
- `variables.tf` — `region` (default "us-east-2"), `user_email`, `instance_type` (default `t3.medium`), `customer_name`, `eks_node_ami_release_version`
- `outputs.tf` — `vpc_id`, `demo_id`, `cluster_endpoint`, `kube_cluster_certificate_authority_data`, `eks_cluster_name` (outputs a `kubectl update-kubeconfig` command using `var.region`), `eks_cluster_id`, `eks_cluster_auth` (sensitive token), `first_private_subnet_id`, `first_public_subnet_id`, `shared_internal_sg_id`, `resources_prefix`

**Note:** `kube0/variables.tf` declares a `region` variable (default `us-east-2`) which is passed from the component. It is used in the `eks_cluster_name` output.

#### `modules/kube1/` — Kubernetes Base Tools
**Providers:** aws, kubernetes, helm, time

**Files:**
- `2_kube_tools.tf` — Vault license K8s secret, 3x EIPs for nginx ingress NLB, `helm_release.nginx_ingress` (ingress-nginx chart), `vault-auth` ServiceAccount with token secret and ClusterRoleBinding for `system:auth-delegator`
- `variables.tf` — `demo_id`, `cluster_endpoint`, `kube_cluster_certificate_authority_data`, `vault_license_key`
- `outputs.tf` — `kube_namespace` (hardcoded `"default"`)

#### `modules/vault/` — Vault Enterprise HA Cluster + VSO
**Providers:** helm, kubernetes

**Files:**
- `vault.tf` — `helm_release.vault_cluster` (Vault Helm chart v0.31.0): HA Raft with 3 nodes, `hashicorp/vault-enterprise:1.21.2-ent`, TLS disabled, EBS storage via custom StorageClass, internal NLB for server, internal NLB for UI, CSI enabled, injector disabled
- `vault_init.tf` — Init K8s job: downloads kubectl/jq, waits for vault-0, runs `vault operator init` (5 shares, 3 threshold), stores init JSON in `vault-init-data` K8s secret, unseals all 3 nodes, joins vault-1/vault-2 to Raft. Also handles re-unseal on already-initialized clusters. Uses RBAC (secret-writer SA, Role, RoleBinding).
- `vso.tf` — VSO Helm chart v0.9.0, creates `VaultConnection` (name: `default`, uses Vault LB hostname), `VaultAuth` (name: `default`, K8s auth method, role `vso-role`, SA `vso-auth`, audience `vault`), `vso-auth` ServiceAccount with `system:auth-delegator` ClusterRoleBinding
- `storage.tf` — `kubernetes_storage_class_v1.vault_storage`: EBS CSI gp3, encrypted, WaitForFirstConsumer
- `variables.tf` — `kube_namespace`, `vault_image_repository` (default `hashicorp/vault-enterprise`), `vault_image_tag` (default `1.21.2-ent`)
- `outputs.tf` — Reads `vault-init-data` secret, parses JSON for `root_token` and `unseal_keys_b64`. Outputs: `vault_unseal_keys` (sensitive), `vault_root_token` (nonsensitive!), `vault_namespace`, `vault_service_name` ("vault"), `vault_initialized`, `vault_loadbalancer_hostname` (http://LB:8200), `vault_ui_loadbalancer_hostname` (http://LB:8200), `vso_vault_auth_name` ("default")

#### `modules/AWS_DC/` — Active Directory Domain Controller
**Providers:** aws, tls, random

**Files:**
- `main.tf` — Windows Server 2022 EC2 (`data.aws_ami.windows_2022`), RSA-4096 keypair for RDP, security group (RDP + Kerberos from allowlist_ip), DSRM password via `random_string`, `random_password.test_user_password` (for_each over 4 test accounts), user_data PowerShell: first boot promotes to DC (`Install-ADDSForest`, domain `mydomain.local`), second boot installs AD CS (`Install-AdcsCertificationAuthority` for LDAPS) and creates test service accounts (svc-rotate-a, svc-rotate-b, svc-single, svc-lib). Elastic IP attached.
- `variables.tf` — `allowlist_ip`, `prefix` (default "boundary-rdp"), `aws_key_pair_name`, `ami` (unused default), `domain_controller_instance_type`, `root_block_device_size` (128GB), `active_directory_domain` (mydomain.local), `active_directory_netbios_name` (mydomain), `only_ntlmv2`, `only_kerberos`, `vpc_id`, `subnet_id`, `shared_internal_sg_id`
- `outputs.tf` — `private-key`, `public-dns-address`, `eip-public-ip`, `dc-priv-ip`, `password` (decrypted admin pw, nonsensitive), `aws_keypair_name`, `test_users` (map of test account details from `random_password`)
- `README.md` — Documents the DC setup and PowerShell user_data

#### `modules/windows_config/` — Windows IPAM + AD User Creation
**Providers:** kubernetes

**Files:**
- `main.tf` — Two K8s jobs:
  1. `windows_k8s_config` (Linux container): Enables Windows IPAM via ConfigMap `amazon-vpc-cni`, sets env on aws-node DaemonSet, waits for VPC CNI rollout, waits for Windows nodes to join and be Ready (up to 10 min), waits 60s for IP allocation
  2. `create_ad_user` (Windows container `ghcr.io/andybaran/aws-vault-ldap-k8s/ad-tools:ltsc2022`): Creates `vault-demo` AD user with PowerShell script from ConfigMap. Uses initial password = admin password. Node selector `kubernetes.io/os=windows`, tolerates `os=windows:NoSchedule` taint. Annotation `demo/dc-private-ip` forces re-creation when DC rebuilds.
- `scripts/Create-ADUser.ps1` — PowerShell: waits for AD on port 389, imports AD module, authenticates as admin, deletes existing vault-demo user if present, creates fresh vault-demo user, verifies and tests auth
- `variables.tf` — `demo_id`, `cluster_endpoint`, `kube_cluster_certificate_authority_data`, `kube_namespace`, `ldap_dc_private_ip`, `ldap_admin_password`
- `outputs.tf` — `windows_ipam_enabled`, `ad_user_job_status` (used as dependency signal), `vault_demo_initial_password`

#### `modules/vault_ldap_secrets/` — Vault LDAP Secrets Engine
**Providers:** vault

**Files:**
- `main.tf` — `vault_ldap_secret_backend.ad`: mounted at `var.secrets_mount_path` (default "ldap"), LDAPS URL, `insecure_tls=true`, schema `ad`, `userattr=cn` (not UPN), `skip_static_role_import_rotation=true`. Static role `demo-service-account` for user `vault-demo`, rotation period configurable (default 300s). Policy `ldap-static-read` granting read on `static-cred/<role>` and list on `static-role/*`.
- `kubernetes_auth.tf` — `vault_auth_backend` type kubernetes at path "kubernetes", config with EKS host/CA cert, role `vso-role` bound to SA `vso-auth` in `kube_namespace`, token TTL 600s, policies `[ldap-static-read]`, audience `vault`
- `variables.tf` — `ldap_url`, `ldap_binddn`, `ldap_bindpass` (sensitive), `ldap_userdn`, `secrets_mount_path`, `active_directory_domain`, `static_role_name` (default "demo-service-account"), `static_role_username` (default "vault-demo"), `static_role_rotation_period` (default 300), `kubernetes_host`, `kubernetes_ca_cert`, `kube_namespace`, `ad_user_job_completed`
- `outputs.tf` — `ldap_secrets_mount_path`, `ldap_secrets_mount_accessor`, `static_role_name`, `static_role_credentials_path`, `static_role_policy_name`

#### `modules/ldap_app/` — Python App Deployment + VSO Integration
**Providers:** kubernetes, time

**Files:**
- `ldap_app.tf` — `VaultDynamicSecret` CR: reads from `<mount>/static-cred/<role>`, `allowStaticCreds=true`, `refreshAfter` at 80% of rotation period, creates K8s secret `ldap-credentials`, triggers rolling restart of deployment. `kubernetes_deployment_v1.ldap_app`: 2 replicas, image `ghcr.io/andybaran/vault-ldap-demo:latest`, port 8080, env vars from secret (LDAP_USERNAME, LDAP_PASSWORD, LDAP_LAST_VAULT_PASSWORD, ROTATION_PERIOD, ROTATION_TTL), liveness/readiness probes on `/health`. `kubernetes_service_v1`: LoadBalancer, port 80→8080. Outputs: `ldap_app_service_name`, `ldap_app_service_type`, `ldap_app_url`
- `variables.tf` — `kube_namespace`, `ldap_mount_path`, `ldap_static_role_name`, `vso_vault_auth_name`, `static_role_rotation_period`, `ldap_app_image` (default `ghcr.io/andybaran/vault-ldap-demo:latest`)

### Python Web Application (`python-app/`)

Flask app (`app.py`) displaying LDAP credentials:
- Reads env vars: `LDAP_USERNAME`, `LDAP_PASSWORD`, `LDAP_LAST_VAULT_PASSWORD`, `ROTATION_PERIOD`, `ROTATION_TTL`
- HDS-styled UI with Vault logo SVG, live countdown timer (JavaScript), progress bar, refresh button (appears 5s after countdown hits zero)
- Health check at `/health`
- `Dockerfile`: multi-stage build, python:3.11-slim, non-root user (UID 1000), port 8080
- `requirements.txt`: Flask==3.1.0, Werkzeug==3.1.3
- Image: `ghcr.io/andybaran/vault-ldap-demo:latest`

### Docker Images (`docker/`)

- `docker/ad-tools/Dockerfile` — Windows Server Core ltsc2022 with RSAT-AD-PowerShell pre-installed
- Image: `ghcr.io/andybaran/aws-vault-ldap-k8s/ad-tools:ltsc2022`

### CI/CD (`.github/workflows/`)

| Workflow | Trigger | Image |
|----------|---------|-------|
| `build-python-app-image.yml` | push to `main` on `python-app/**` | `ghcr.io/andybaran/vault-ldap-demo` |
| `build-ad-tools-image.yml` | push to `main` on `docker/ad-tools/**` | `ghcr.io/andybaran/aws-vault-ldap-k8s/ad-tools` |

### Stack Outputs (from `components.tfcomponent.hcl`)

- `public-dns-address` — DC Elastic IP public DNS
- `ldap-eip-public-ip` — DC Elastic IP
- `ldap-private-ip` — DC private IP
- `password` — Decrypted DC admin password
- `eks_cluster_name` — EKS cluster name (kubectl command)
- `vault_service_name` — "vault"
- `vault_loadbalancer_hostname` — Vault API internal LB
- `vault_ui_loadbalancer_hostname` — Vault UI internal LB
- `vault_root_token` — Vault root token (sensitive)
- `vault_ldap_secrets_path` — LDAP secrets mount path
- `ldap_app_service_name` — K8s service name for the app
- `ldap_app_access_info` — App LoadBalancer URL

### Key Configuration Values

- **VPC CIDR:** 10.0.0.0/16
- **AD Domain:** mydomain.local (NetBIOS: mydomain)
- **AD User managed by Vault:** vault-demo
- **LDAP bind DN:** CN=Administrator,CN=Users,DC=mydomain,DC=local
- **Vault static role name:** demo-service-account
- **VSO auth role:** vso-role (bound to SA `vso-auth`)
- **VSO VaultAuth/VaultConnection names:** "default"
- **Kubernetes auth path in Vault:** "kubernetes"
- **Rotation period:** 30s (set in `components.tfcomponent.hcl` for both `vault_ldap_secrets` and `ldap_app`)
- **Deployment region:** us-east-2
- **Customer name:** fidelity (truncated to 4 chars: "fide")
- **Instance type:** c5.xlarge (for deployment), t3.medium (default in module)
- **EKS AMI release:** 1.34.2-20260128

### Known Issues / Notes

1. **Vault root token exposed as nonsensitive** — `vault_root_token` output uses `nonsensitive()` wrapper. Acceptable for demo but noted.

#### Resolved (PR #147)
- ~~Missing `random_password` resource in AWS_DC~~ — Added `random_password.test_user_password` with `for_each`
- ~~Stale `vault_init_keys` data source~~ — Removed from `vault_init.tf`
- ~~`kube0` missing `region` variable / hardcoded region in output~~ — Added `region` var, parameterized `eks_cluster_name`
- ~~Hardcoded `allowlist_ip`~~ — Extracted to stack variable `allowlist_ip`, value moved to `deployments.tfdeploy.hcl`

## Resources to Use for Reference

- Terraform Documentation: https://developer.hashicorp.com/terraform/docs
- HCL Documentation: https://developer.hashicorp.com/hcl
- AWS Documentation: https://docs.aws.amazon.com/
- Vault Secrets Operator: https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso
- Vault Secrets Operator Protected Secrets: https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/csi
- Vault LDAP Secrets Engine: https://developer.hashicorp.com/vault/docs/secrets/ldap
- Terraform Stacks: https://developer.hashicorp.com/terraform/language/stacks
- Terraform Stacks Organization: https://developer.hashicorp.com/validated-designs/terraform-operating-guides-adoption/organizing-resources#terraform-stacks
