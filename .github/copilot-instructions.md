---
applyTo: "*.tf,*.hcl,*.md"
---


The goal of this project is to create an infrastructre as code demo using Terraform, HCL, AWS, EKS, and Vault with LDAP integration.  The LDAP integration is intended to demonstrate how to securely manage user access to Vault using an existing Active Directory LDAP directory.  More specifically, we need to demonstrate Vault configured with static roles that manage the password rotation of an Active Directory account.  Those credentials will then be delivered to a simple python application using Vault Protected Secrets Operator deployed in the EKS cluster. The python application needs to display the secrets delivered to it from Vault via the Vault Secrets Operator on a webpage.  Much of the code in this project has already been generated and is known to work.  We now need to focus on adding the additional functionality to complete the demo.  The code currently utilizes Terraform Stacks and your work needs to continue to do so.

When generating or suggesting code for this project, please adhere to the following guidelines:

- Follow terraform and HCL best practices for formatting and structuring code.
- Code should be clear, concise, and maintainable.
- Use comments to explain complex logic or decisions in the code.
- While security is important, avoid overcomplicating the code with excessive security measures that may hinder readability or maintainability.  This is a demo project not meant for production use.
- When suggesting changes, ensure they align with the project's goals and existing architecture.
- Provide explanations for your code suggestions to help understand the reasoning behind them.
- Do research to ensure the latest and most efficient methods are used in the code. Particularly in regards to AWS services, Terraform providers, Terraform Modules and Terraform Stacks.
- When there is conflicting information regarding best practices or implementation details, prioritize official documentation skills and plugins from HashiCorp and AWS, including the local Terraform MCP server.
- Ask me clarifying questions one by one and wait for me to answer before asking another.
- Use the model Claude Opus 4.5 when generating code for this project.
- Do not commit directly to the main branch.
- I have set the correct environment variables to log into AWS.
- If you need credentials, prompt me for them and wait for my answer.

## Branching Strategy (Gitflow)
- **main**: Production-ready code. Never commit directly.
- **develop**: Integration branch. Feature branches merge here first via PR.
- **feature/***: Created from `develop` for new work. Named `feature/<description>-issue-<N>`.
- **fix/***: Created from `develop` for bug fixes.
- When a feature is complete, create a PR from `feature/*` → `develop`.
- When `develop` is stable and ready for production, create a PR from `develop` → `main`.
- Always notify the user and wait for approval before merging to `main`.

## Workflow
- Start by doing a thorough review of the existing code.
- Then create a ToDo list and then open a github issue for each item on the list.
- When you are ready to work on an issue, create a feature branch from `develop`.
- Working in parallel on multiple issues is preferred; if there are similar ToDo's or github issues, group them and work them in parallel.
- When you are done working on an issue, make a PR to `develop` and close the issue.
- If subsequent issues depend on the issue you just closed, notify me and wait for me to approve a merge to `develop`.
- Periodically (or when a set of features is complete), create a PR from `develop` → `main` for release.

## Resources to use for reference:
- Terraform Documentation: https://developer.hashicorp.com/terraform/docs
- HCL Documentation: https://developer.hashicorp.com/hcl
- AWS Documentation: https://docs.aws.amazon.com/
- Vault Secrets Operator: https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso
- Vault Secrets Operator Protected Secrets: https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/csi
- Vault LDAP Secrets Engine: https://developer.hashicorp.com/vault/docs/secrets/ldap
- Terraform Stacks: https://developer.hashicorp.com/terraform/language/stacks
- Terraform Stacks Organization: https://developer.hashicorp.com/validated-designs/terraform-operating-guides-adoption/organizing-resources#terraform-stacks

---

## Codebase Reference Notes (for session continuity)

### Repository Overview
- **Repo**: `andybaran/aws-vault-ldap-k8s` (GitHub, SSH)
- **Purpose**: Terraform Stacks demo — Vault LDAP secrets engine + AD password rotation + VSO + EKS + Python web app
- **Terraform version**: 1.14.2 (stacks-enabled)
- **Deployment target**: HCP Terraform (uses variable sets for AWS creds & Vault license)
- **Region**: us-east-2, customer_name: "fidelity", instance_type: c5.xlarge

### Terraform Stacks Architecture
The project uses **Terraform Stacks** (not standard root modules). Key files at repo root:

| File | Purpose |
|------|---------|
| `components.tfcomponent.hcl` | Defines all stack components and their input/output wiring |
| `deployments.tfdeploy.hcl` | Deployment configuration (region, varsets, inputs) |
| `providers.tfcomponent.hcl` | Provider definitions (aws, vault, kubernetes, helm, etc.) |
| `variables.tfcomponent.hcl` | Stack-level variable declarations |

### Component Dependency Graph
```
kube0 (VPC, EKS, SGs)
  ├──► kube1 (nginx ingress, vault SA, vault license secret)
  │      └──► vault_cluster (Vault Helm, init job, VSO Helm, VaultConnection, VaultAuth)
  │             ├──► vault_ldap_secrets (LDAP secrets engine, static role, k8s auth backend)
  │             │      └──► ldap_app (VaultDynamicSecret CR, Deployment, Service)
  │             └──► [providers.tfcomponent.hcl: vault provider uses vault_cluster outputs]
  ├──► ldap (AWS_DC: Windows EC2 domain controller, AD forest, AD CS for LDAPS)
  │      └──► windows_config (enable Windows IPAM, create vault-demo AD user via K8s job)
  │             └──► vault_ldap_secrets (depends on ad_user_job_completed)
  ├──► admin_vm (bastion host, uses ldap's keypair)
  └──► windows_config (uses kube0 + kube1 + ldap outputs)
```

### Module Details

#### `modules/kube0/` — EKS + VPC Foundation
- **VPC**: 10.0.0.0/16 via `terraform-aws-modules/vpc/aws` v6.5.1, single NAT gateway
- **EKS**: `terraform-aws-modules/eks/aws` v21.11.0, Kubernetes 1.34
- **Node groups**: `linux_nodes` (c5.xlarge, 3 desired) + `windows_nodes` (t3.large, 1 desired, tainted `os=windows:NoSchedule`)
- **EKS Addons**: coredns, eks-pod-identity-agent, kube-proxy, vpc-cni, aws-ebs-csi-driver
- **Outputs**: vpc_id, cluster_endpoint, CA data, auth token, subnet IDs, shared SG ID, resources_prefix
- **Naming**: `{customer_name_4chars}-{random4}-secrets-operator` prefix

#### `modules/kube1/` — Kubernetes Tooling Layer
- Installs **nginx-ingress** controller (Helm) with 3 EIPs + NLB
- Creates **vault-auth** ServiceAccount + token secret + ClusterRoleBinding (auth-delegator)
- Creates **vault-license** Kubernetes secret from var
- **Namespace**: hardcoded `"default"` for all resources
- Outputs: `kube_namespace` (always "default")

#### `modules/vault/` — Vault Cluster
- **Helm chart**: `hashicorp/vault` v0.31.0, image `hashicorp/vault-enterprise:1.21.2-ent`
- **HA mode**: Raft with 3 nodes (vault-0, vault-1, vault-2), setNodeId=true
- **Storage**: Custom StorageClass `vault-storage` (gp3 EBS via CSI, 10Gi data + 10Gi audit)
- **Services**: LoadBalancer (internal NLB) for API + separate UI LoadBalancer
- **TLS**: Disabled (`global.tlsDisable=true`), skip_tls_verify on provider
- **Init**: K8s Job downloads kubectl+jq, initializes vault-0, joins+unseals vault-1 & vault-2, stores init data in `vault-init-data` K8s secret
- **VSO**: `vault-secrets-operator` Helm v0.9.0, creates VaultConnection (`http://LB:8200`) + VaultAuth (k8s auth, role=`vso-role`, SA=`vso-auth`)
- **Injector**: Disabled, CSI: Enabled
- Outputs: root_token (nonsensitive!), LB hostnames, namespace, service name, vso_vault_auth_name

#### `modules/AWS_DC/` — Active Directory Domain Controller
- Windows Server 2022 EC2 in **public subnet** with EIP
- User_data: first boot promotes to DC (`mydomain.local`), second boot installs **AD CS** (Enterprise Root CA for LDAPS)
- Uses `<persist>true</persist>` to re-run user_data on reboot
- Security groups: RDP (3389) + Kerberos (88) from allowlist IP + shared internal SG
- Generates TLS keypair for AWS password decryption
- Outputs: private IP, public DNS/IP, decrypted admin password, keypair name, private key

#### `modules/windows_config/` — Windows IPAM + AD User Setup
- **Job 1** (`windows-k8s-config`): Linux container that enables Windows IPAM via ConfigMap + DaemonSet env, waits for Windows nodes to be Ready
- **Job 2** (`create-ad-user`): Windows container (`ghcr.io/andybaran/aws-vault-ldap-k8s/ad-tools:ltsc2022`) runs `Create-ADUser.ps1`
  - Creates `vault-demo` user in AD with Administrator's password as initial password
  - Deletes existing user first if present (demo mode)
  - Annotation `demo/dc-private-ip` forces job re-creation when DC is rebuilt
- Outputs: `ad_user_job_status` (used as dependency by vault_ldap_secrets)

#### `modules/vault_ldap_secrets/` — Vault LDAP Secrets Engine
- Mounts LDAP secrets engine at path `ldap` with AD schema
- **Connection**: LDAPS (`ldaps://<DC_IP>`) with `insecure_tls=true`, `userattr=cn`
- **Static role**: `demo-service-account` for user `vault-demo`, rotation_period=10s (set in components.tfcomponent.hcl)
- **Policy**: `ldap-static-read` — allows reading `ldap/static-cred/demo-service-account`
- **K8s Auth**: Enables `kubernetes` auth backend, configures backend with EKS endpoint+CA
- **K8s Auth Role**: `vso-role` bound to SA `vso-auth` in default namespace, policies=[ldap-static-read], audience=vault
- Outputs: mount_path, accessor, role_name, credentials_path, policy_name

#### `modules/ldap_app/` — Python Web App Deployment
- **VaultDynamicSecret CR**: reads `ldap/static-cred/demo-service-account`, creates K8s secret `ldap-credentials`, renewalPercent=67
- **Deployment**: 2 replicas, image `ghcr.io/andybaran/vault-ldap-demo:latest`, port 8080
- **Env vars from secret**: LDAP_USERNAME, LDAP_PASSWORD, LDAP_LAST_VAULT_PASSWORD, ROTATION_PERIOD, ROTATION_TTL
- **Service**: LoadBalancer on port 80→8080
- **Probes**: liveness+readiness on /health
- **Rollout restart**: VSO triggers rolling restart on credential rotation

#### `modules/admin_vm/` — Admin Bastion Host
- Amazon Linux 2023 EC2 in **private subnet** with EIP
- Installs: Vault CLI 1.21.2, kubectl, AWS CLI v2, Helm
- Uses shared keypair from ldap module + shared internal SG
- Outputs: public/private IPs, DNS, SSH command, SSH private key

### Python App (`python-app/`)
- Flask app on port 8080, reads env vars for LDAP creds
- HashiCorp-styled UI with live countdown timer to next rotation
- Docker image: multi-stage build, python:3.11-slim, non-root user
- Published to `ghcr.io/andybaran/vault-ldap-demo`

### Docker Images
- **Python app**: `ghcr.io/andybaran/vault-ldap-demo:latest` (linux/amd64, built on push to python-app/)
- **AD tools**: `ghcr.io/andybaran/aws-vault-ldap-k8s/ad-tools:ltsc2022` (Windows, built on push to docker/ad-tools/)

### CI/CD (GitHub Actions)
- `.github/workflows/build-python-app-image.yml`: Builds python-app on push to main
- `.github/workflows/build-ad-tools-image.yml`: Builds Windows ad-tools image on push to main

### Provider Versions (pinned in providers.tfcomponent.hcl)
- aws: 6.27.0
- vault: 5.6.0
- kubernetes: 3.0.1
- helm: 3.1.1
- tls: ~> 4.0.5
- random: ~> 3.6.0
- http: ~> 3.5.0
- cloudinit: 2.3.7
- null: 3.2.4
- time: 0.13.1

### HCP Terraform Configuration
- **Variable sets**: `aws_creds` (varset-oUu39eyQUoDbmxE1, env category), `vault_license` (varset-fMrcJCnqUd6q4D9C, terraform category)
- **Deployment**: `development` in us-east-2
- **EKS AMI**: 1.34.2-20260128

### Key Design Decisions & Gotchas
1. **All K8s resources in `default` namespace** — hardcoded throughout
2. **Vault root token is nonsensitive** in outputs — intentional for demo
3. **LDAPS via AD CS**: DC user_data installs AD CS on second boot (after DC promotion reboot) to auto-enroll LDAPS cert on port 636
4. **Static role rotation_period=10** in components.tfcomponent.hcl (overrides default 300 in variables.tf) — very fast for demo
5. **VaultDynamicSecret (not VaultStaticSecret)** is used in ldap_app despite the README saying VaultStaticSecret — the CRD kind is `VaultDynamicSecret` with path `static-cred/...`
6. **Admin VM in private subnet** but has EIP for SSH access
7. **DC in public subnet** with EIP for RDP access
8. **Windows nodes**: tainted with `os=windows:NoSchedule`, AD user job tolerates this
9. **Allowlist IP hardcoded**: `66.190.197.168/32` in components.tfcomponent.hcl (Andy's IP)
10. **`prefix` variable passed twice** to ldap component in components.tfcomponent.hcl (both `var.customer_name` and `component.kube0.resources_prefix`)
11. **Duplicate `vault_root_token` output**: one active, one commented out at bottom of components.tfcomponent.hcl
12. **`eks_cluster_name` output** is actually a `kubectl update-kubeconfig` command, not just the cluster name
13. **No `region` variable** passed to kube0's `eks_cluster_name` output — it's hardcoded to `us-east-2`
14. **`vault_init_keys` data source** in vault_init.tf references a secret named `vault-init-keys` but the job creates `vault-init-data` — this is a stale reference (the actual data is read from `vault-init-data` in outputs.tf)

### Existing Branch History
- ~50 merged feature/fix branches exist (issues #23-#114 all closed)
- No open issues currently
- Branch `copilot-improvements` exists but is separate from current work
