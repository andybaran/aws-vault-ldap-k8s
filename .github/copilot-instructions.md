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

### Agent Status Dashboard Integration

The agent status dashboard runs at a configurable URL (default: http://localhost:5050). Every agent participating in this project must report its status to the dashboard using the following API:

**API Endpoint:**
```
POST http://localhost:5050/api/update/<agent_name>/<status>
```

**Valid Statuses:**
- `working` - Agent is actively executing a task
- `waiting` - Agent is blocked or waiting for dependencies
- `completed` - Agent has successfully completed its task
- `idle` - Agent is available but not assigned work
- `blocked` - Agent cannot proceed due to external factors
- `error` - Agent encountered an error

**Optional Query Parameters:**
- `task` - Name or brief description of the current task
- `task_url` - Link to related issue, PR, or documentation
- `model` - AI model being used (e.g. Claude Sonnet 4.5, GPT-4.1)

**Example curl commands:**
```bash
# Report working status with task details and model
curl -s -X POST "http://localhost:5050/api/update/Terraform%20Agent/working?task=Updating%20EKS%20module%20version&task_url=https://github.com/andybaran/aws-vault-ldap-k8s/issues/42&model=Claude+Opus+4.5" > /dev/null

# Report completed status
curl -s -X POST "http://localhost:5050/api/update/Terraform%20Agent/completed" > /dev/null

# Report error status with details
curl -s -X POST "http://localhost:5050/api/update/Vault%20Agent/error?task=Vault%20init%20job%20failed&model=Claude+Haiku+4.5" > /dev/null
```

**Naming Convention:**
- Use Title Case for agent names (e.g., "Terraform Agent", "Vault Agent")
- Be consistent with agent names across all status updates
- URL-encode agent names in the API path (spaces become `%20`)

**Required Lifecycle:**
1. Agent reports `working` status when starting a task
2. Agent performs work, optionally updating status with progress
3. Agent reports `completed` status on success, or `error` on failure
4. If blocked waiting for another agent, report `waiting` status

**Stale Threshold:**
- If an agent does not report status for 10 minutes, it will be marked as stale
- The Time Tracking Agent monitors for stale agents and investigates

### Agent Definitions

This project employs 10 specialized agents, each with specific responsibilities. All agents coordinate through the status dashboard and follow the orchestration rules defined below.

| Agent Name | Responsibility |
|---|---|
| Terraform Agent | Write/modify Terraform Stacks HCL (components, deployments, providers, variables) and all modules; ensure provider version pins and module upgrades follow best practices |
| AWS Agent | Manage AWS-specific resources (VPC, EKS, security groups, EC2 domain controller, EIPs, IAM roles) and troubleshoot AWS service issues |
| Vault Agent | Configure Vault Enterprise HA Raft cluster, VSO, Vault Agent sidecars, CSI Driver, LDAP secrets engine, K8s auth, and dual-account rotation plugin |
| Kubernetes Agent | Manage Kubernetes resources (deployments, services, ServiceAccounts, RBAC, Helm releases, storage classes) and EKS cluster configuration |
| Python App Agent | Develop and maintain the Flask credential display app (app.py, Dockerfile, requirements.txt), including VSO, Vault Agent, and CSI delivery modes |
| Documentation Agent | Update copilot-instructions.md, README files, PR descriptions, code comments, and module READMEs whenever changes are made |
| Testing Agent | Validate Terraform plans, test deployed infrastructure end-to-end, verify credential rotation, and troubleshoot deployment failures |
| Windows Agent | Manage the Active Directory domain controller (EC2 user_data, PowerShell scripts, AD CS, LDAPS), Windows IPAM, and AD user creation K8s jobs |
| GitOps Agent | Coordinate branches, PRs, GitHub issues, merge orchestration, and ensure main branch stays deployable |
| Time Tracking Agent | Monitor agent status dashboard, report anomalies, ensure all agents report correctly, and investigate stale agents |

#### Terraform Agent

The Terraform Agent is responsible for all Terraform Stacks HCL and module development. This includes `components.tfcomponent.hcl`, `deployments.tfdeploy.hcl`, `providers.tfcomponent.hcl`, `variables.tfcomponent.hcl`, and all files under `modules/`. The agent ensures provider versions are pinned, module inputs/outputs are correctly wired, and the component dependency graph is maintained.

**Key Responsibilities:**
- Modify stack-level HCL files (component definitions, deployment configs, provider pins, variable declarations)
- Update Terraform module code in `modules/kube0/`, `modules/kube1/`, `modules/vault/`, `modules/vault_ldap_secrets/`, `modules/ldap_app/`, `modules/AWS_DC/`, and `modules/windows_config/`
- Bump provider and module versions (e.g., terraform-aws-modules/eks/aws, terraform-aws-modules/vpc/aws)
- Ensure component dependency wiring is correct in `components.tfcomponent.hcl`
- Coordinate with the AWS Agent for AWS resources and the Vault Agent for Vault configuration

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/Terraform%20Agent/working?task=Bumping%20EKS%20module%20to%20v21.12.0" > /dev/null
curl -s -X POST "http://localhost:5050/api/update/Terraform%20Agent/completed" > /dev/null
```

#### AWS Agent

The AWS Agent manages all AWS-specific infrastructure including VPC networking, EKS cluster configuration, security groups, EC2 instances (Windows domain controller), Elastic IPs, IAM roles (IRSA for EBS CSI), and EKS addons. The agent troubleshoots AWS service issues and ensures resources are cost-effective for this demo project.

**Key Responsibilities:**
- Configure VPC (CIDR, subnets, NAT gateway) in `modules/kube0/1_aws_network.tf`
- Manage EKS cluster (version, node groups, addons) in `modules/kube0/1_aws_eks.tf`
- Maintain security groups in `modules/kube0/2_security_groups.tf`
- Manage the Windows EC2 domain controller AMI, instance type, and EIP in `modules/AWS_DC/`
- Coordinate with the Terraform Agent for HCL changes and the Windows Agent for DC configuration

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/AWS%20Agent/working?task=Updating%20EKS%20addons%20for%20K8s%201.34" > /dev/null
curl -s -X POST "http://localhost:5050/api/update/AWS%20Agent/completed" > /dev/null
```

#### Vault Agent

The Vault Agent configures all Vault Enterprise components: the HA Raft cluster via Helm, the init/unseal job, Vault Secrets Operator (VSO), VaultConnection/VaultAuth CRDs, the CSI Driver, the LDAP secrets engine (single and dual-account modes), Kubernetes auth backend, and the custom dual-account rotation plugin registration.

**Key Responsibilities:**
- Manage Vault Helm release configuration in `modules/vault/vault.tf`
- Maintain the init/unseal K8s job in `modules/vault/vault_init.tf`
- Configure VSO, VaultConnection, and VaultAuth in `modules/vault/vso.tf`
- Set up LDAP secrets engine (single-account in `modules/vault_ldap_secrets/main.tf`, dual-account in `modules/vault_ldap_secrets/dual_account.tf`)
- Manage K8s auth backend and roles in `modules/vault_ldap_secrets/kubernetes_auth.tf`
- Coordinate with the Kubernetes Agent for K8s resources and the Python App Agent for secret delivery

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/Vault%20Agent/working?task=Configuring%20dual-account%20static%20roles" > /dev/null
curl -s -X POST "http://localhost:5050/api/update/Vault%20Agent/completed" > /dev/null
```

#### Kubernetes Agent

The Kubernetes Agent manages all Kubernetes-level resources including deployments, services, ServiceAccounts, RBAC (Roles, RoleBindings, ClusterRoleBindings), Helm chart releases, StorageClasses, ConfigMaps, and Secrets. This agent also handles EKS-specific configuration like Windows node management and VPC CNI settings.

**Key Responsibilities:**
- Manage nginx ingress Helm release and EIPs in `modules/kube1/`
- Configure Vault storage class in `modules/vault/storage.tf`
- Maintain app deployments (VSO, Vault Agent sidecar, CSI) in `modules/ldap_app/`
- Manage ServiceAccounts and RBAC for Vault auth, VSO, and app workloads
- Handle Windows node scheduling (taints, tolerations, node selectors) in `modules/windows_config/`
- Coordinate with the Vault Agent for auth configuration and the AWS Agent for EKS changes

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/Kubernetes%20Agent/working?task=Updating%20nginx%20ingress%20Helm%20values" > /dev/null
curl -s -X POST "http://localhost:5050/api/update/Kubernetes%20Agent/completed" > /dev/null
```

#### Python App Agent

The Python App Agent develops and maintains the Flask credential display application in `python-app/`. This includes `app.py` (3 delivery modes: VSO, Vault Agent sidecar, CSI Driver), the `Dockerfile`, `requirements.txt`, and the HDS-styled UI with timeline visualization. The agent ensures the app correctly handles dual-account rotation and all secret delivery methods.

**Key Responsibilities:**
- Maintain `python-app/app.py` including VaultClient, FileCredentialCache, and credential API
- Update `python-app/Dockerfile` and `python-app/requirements.txt`
- Ensure the timeline UI correctly visualizes Account A/B rotation phases
- Test all three delivery modes locally before deployment
- Coordinate with the Vault Agent for secret paths and the Kubernetes Agent for deployment specs

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/Python%20App%20Agent/working?task=Adding%20CSI%20Driver%20delivery%20mode" > /dev/null
curl -s -X POST "http://localhost:5050/api/update/Python%20App%20Agent/completed" > /dev/null
```

#### Documentation Agent

The Documentation Agent maintains all documentation: this `copilot-instructions.md` (including the Codebase Snapshot), module READMEs, PR descriptions, and code comments. The agent ensures documentation stays current with code changes, particularly the Codebase Snapshot section which serves as the primary context for future sessions.

**Key Responsibilities:**
- Update the Codebase Snapshot section in copilot-instructions.md after every PR
- Write clear PR descriptions with change summaries and testing notes
- Maintain module-level READMEs (e.g., `modules/AWS_DC/README.md`)
- Add inline comments for complex logic (dual-account gating, Vault init, PowerShell user_data)
- Coordinate with all agents to capture changes and update documentation promptly

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/Documentation%20Agent/working?task=Updating%20Codebase%20Snapshot%20for%20PR%20195" > /dev/null
curl -s -X POST "http://localhost:5050/api/update/Documentation%20Agent/completed" > /dev/null
```

#### Testing Agent

The Testing Agent validates Terraform plans, tests deployed infrastructure end-to-end, verifies credential rotation works correctly, and troubleshoots deployment failures. The agent runs `terraform plan` to catch configuration errors and performs smoke tests against the live stack (Vault API, LDAP rotation, app endpoints).

**Key Responsibilities:**
- Run Terraform plan/apply validation for all stack components
- Verify Vault initialization, unsealing, and LDAP secrets engine configuration
- Test credential rotation (single-account and dual-account modes)
- Smoke test the Python app endpoints (`/health`, `/api/credentials`) for all delivery methods
- Investigate and resolve "Unexpected Identity Change" Terraform Stacks errors
- Coordinate with the Terraform Agent for plan validation and the Vault Agent for secrets engine testing

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/Testing%20Agent/working?task=Verifying%20dual-account%20rotation%20end-to-end" > /dev/null
curl -s -X POST "http://localhost:5050/api/update/Testing%20Agent/completed" > /dev/null
```

#### Windows Agent

The Windows Agent manages everything related to the Active Directory domain controller: the Windows Server 2022 EC2 instance, PowerShell user_data scripts (AD DS forest promotion, AD CS for LDAPS, test service account creation), the Windows IPAM K8s job, and the AD user creation K8s job running on Windows nodes.

**Key Responsibilities:**
- Maintain Windows EC2 user_data PowerShell in `modules/AWS_DC/main.tf`
- Manage AD service accounts (svc-rotate-a through svc-rotate-f, svc-single, svc-lib)
- Configure AD Certificate Services for LDAPS connectivity
- Maintain the `Create-ADUser.ps1` script in `modules/windows_config/scripts/`
- Manage the Windows IPAM enablement and Windows node scheduling K8s jobs
- Coordinate with the AWS Agent for EC2 configuration and the Vault Agent for LDAP bind credentials

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/Windows%20Agent/working?task=Updating%20AD%20service%20account%20creation%20script" > /dev/null
curl -s -X POST "http://localhost:5050/api/update/Windows%20Agent/completed" > /dev/null
```

#### GitOps Agent

The GitOps Agent coordinates all Git and GitHub operations including branch management, pull request creation, issue tracking, merge orchestration, and ensuring the main branch stays deployable. The agent follows gitflow and ensures all PRs are reviewed before merging.

**Key Responsibilities:**
- Create feature branches for new work
- Create PRs to main with clear descriptions
- Track GitHub issues and link them to PRs
- Coordinate merge timing between dependent changes
- Ensure main branch is always in a deployable state
- Coordinate with all agents to ensure changes are properly committed

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/GitOps%20Agent/working?task=Creating%20PR%20for%20EKS%20upgrade" > /dev/null
curl -s -X POST "http://localhost:5050/api/update/GitOps%20Agent/completed" > /dev/null
```

#### Time Tracking Agent

The Time Tracking Agent monitors the agent status dashboard for anomalies, stale agents, and inconsistent status reporting. It ensures all agents are reporting correctly and investigates when agents fail to update their status within the 10-minute stale threshold.

**Key Responsibilities:**
- Poll the dashboard API every 5-10 minutes to check agent statuses
- Identify agents that have not reported status in 10+ minutes (stale)
- Report anomalies to the user or trigger alerts
- Validate that agent lifecycles follow the expected pattern (working → completed/error)
- Coordinate with all agents to ensure consistent status reporting

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/Time%20Tracking%20Agent/working?task=Monitoring%20dashboard%20for%20stale%20agents" > /dev/null
curl -s -X POST "http://localhost:5050/api/update/Time%20Tracking%20Agent/completed" > /dev/null
```

### Orchestration Rules

1. **Research First:** Review this copilot-instructions.md Codebase Snapshot for full context before making changes. Do NOT re-read the entire codebase.

2. **Human Approval Required:** All PRs to main must be reviewed and approved by a human. No automated merges to main.

3. **Gitflow:** Follow gitflow branching strategy. Create feature branches for all new work. Merge to main only after human review.

4. **Agent Blocking:** When an agent is blocked waiting for another agent to complete work, report `waiting` status with details.

5. **Parallel Work:** When possible, parallelize work across agents. For example, the Documentation Agent can update docs while the Testing Agent validates infrastructure.

6. **Status Reporting:** All agents must report status at the start of work (`working`), at completion (`completed`/`error`), and when blocked (`waiting`). Agents should update status periodically for long-running tasks.

7. **Dependency Order:** Typical workflow follows this pattern:
   - Terraform Agent + AWS Agent → Vault Agent + Kubernetes Agent → Python App Agent → Testing Agent → Documentation Agent → GitOps Agent
   - Windows Agent supports AD-related work independently
   - Time Tracking Agent monitors continuously

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

## Codebase Snapshot (last updated: 2026-03-01, post Phase 5 dual-account expansion)

### Repository

- **GitHub:** `andybaran/aws-vault-ldap-k8s`
- **Default branch:** `main`
- **Terraform version:** 1.14.2 (stacks-enabled)

### Stack-Level Files (root)

| File | Purpose |
|------|---------|
| `components.tfcomponent.hcl` | Defines 6 stack components, their inputs/outputs, provider bindings, and dependency wiring |
| `deployments.tfdeploy.hcl` | Single `development` deployment targeting `us-east-2`, references HCP Terraform varsets `varset-oUu39eyQUoDbmxE1` (aws_creds) and `varset-fMrcJCnqUd6q4D9C` (vault_license) |
| `providers.tfcomponent.hcl` | All provider definitions with pinned versions |
| `variables.tfcomponent.hcl` | Stack-level variable declarations (region, customer_name, AWS creds as ephemeral, vault_license_key, eks_node_ami_release_version, allowlist_ip, vault_image, ldap_app_image, ldap_app_account_name, ldap_dual_account, grace_period) |

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
  │      └──► vault_cluster (Vault Helm HA Raft, init job, VSO, VaultConnection, VaultAuth, CSI Driver)
  │             ├──► vault_ldap_secrets (LDAP engine OR custom dual-account plugin, 3 dual-account static roles: dual-rotation-demo (a/b), vault-agent-dual-role (c/d), csi-dual-role (e/f), K8s auth backend with 4 roles)
  │             │      └──► ldap_app (3 deployments: VSO dual-account, Vault Agent sidecar, CSI Driver)
  │             └──► [vault provider configured from var.vault_address + var.vault_token]
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
- `vault.tf` — `helm_release.vault_cluster` (Vault Helm chart v0.31.0): HA Raft with 3 nodes, `hashicorp/vault-enterprise:1.21.2-ent`, TLS disabled, EBS storage via custom StorageClass, internal NLB for server, internal NLB for UI, CSI enabled, injector disabled. When `ldap_dual_account=true`, overrides HA Raft config to include `plugin_directory = "/vault/plugins"`.
- `vault_init.tf` — Init K8s job: downloads kubectl/jq, waits for vault-0, runs `vault operator init` (5 shares, 3 threshold), stores init JSON in `vault-init-data` K8s secret, unseals all 3 nodes, joins vault-1/vault-2 to Raft. Also handles re-unseal on already-initialized clusters. Uses RBAC (secret-writer SA, Role, RoleBinding).
- `vso.tf` — VSO Helm chart v0.9.0, creates `VaultConnection` (name: `default`, uses Vault LB hostname), `VaultAuth` (name: `default`, K8s auth method, role `vso-role`, SA `vso-auth`, audience `vault`), `vso-auth` ServiceAccount with `system:auth-delegator` ClusterRoleBinding
- `storage.tf` — `kubernetes_storage_class_v1.vault_storage`: EBS CSI gp3, encrypted, WaitForFirstConsumer
- `variables.tf` — `kube_namespace`, `vault_image` (default `hashicorp/vault-enterprise:1.21.2-ent`), `ldap_dual_account` (bool). Locals parse the image into `vault_repository` and `vault_tag` for Helm values.
- `outputs.tf` — Reads `vault-init-data` secret, parses JSON for `root_token` and `unseal_keys_b64`. Outputs: `vault_unseal_keys` (sensitive), `vault_root_token` (nonsensitive!), `vault_namespace`, `vault_service_name` ("vault"), `vault_initialized`, `vault_loadbalancer_hostname` (http://LB:8200), `vault_ui_loadbalancer_hostname` (http://LB:8200), `vso_vault_auth_name` ("default")

#### `modules/AWS_DC/` — Active Directory Domain Controller
**Providers:** aws, tls, random

**Files:**
- `main.tf` — Windows Server 2022 EC2 (`data.aws_ami.windows_2022`), RSA-4096 keypair for RDP, security group (RDP + Kerberos from allowlist_ip), DSRM password via `random_string`, `random_password.test_user_password` (for_each over 8 test accounts), user_data PowerShell: first boot promotes to DC (`Install-ADDSForest`, domain `mydomain.local`), second boot installs AD CS (`Install-AdcsCertificationAuthority` for LDAPS) and creates test service accounts (svc-rotate-a through svc-rotate-f, svc-single, svc-lib). Elastic IP attached. **`time_sleep.wait_for_dc_reboot` (10m) ensures reboot cycle completes before outputs become available.**
- `variables.tf` — `allowlist_ip`, `prefix` (default "boundary-rdp"), `aws_key_pair_name`, `ami` (unused default), `domain_controller_instance_type`, `root_block_device_size` (128GB), `active_directory_domain` (mydomain.local), `active_directory_netbios_name` (mydomain), `only_ntlmv2`, `only_kerberos`, `vpc_id`, `subnet_id`, `shared_internal_sg_id`
- `outputs.tf` — `private-key`, `public-dns-address`, `eip-public-ip`, `dc-priv-ip`, `password` (decrypted admin pw, nonsensitive), `aws_keypair_name`, `static_roles` (map of test account username/password/dn from `random_password`). **All outputs depend on `time_sleep.wait_for_dc_reboot`.**
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

**Modes:** Single-account (default, `ldap_dual_account=false`) and dual-account (`ldap_dual_account=true`). Resources are gated with `count` guards.

**Files:**
- `main.tf` — Single-account mode: `vault_ldap_secret_backend.ad` mounted at `var.secrets_mount_path` (default "ldap"), LDAPS URL, `insecure_tls=true`, schema `ad`, `userattr=cn`, `skip_static_role_import_rotation=true`. Static role for configurable user, rotation period configurable (default 300s). Resources gated with `count = var.ldap_dual_account ? 0 : 1`.
- `dual_account.tf` — Dual-account mode: registers custom plugin (`vault_generic_endpoint` at `sys/plugins/catalog/secret/ldap_dual_account`), mounts via `vault_mount` with `type = "ldap_dual_account"` at path "ldap", configures LDAP backend, creates 3 dual-account static roles: `dual-rotation-demo` (svc-rotate-a/b for VSO), `vault-agent-dual-role` (svc-rotate-c/d for Vault Agent), `csi-dual-role` (svc-rotate-e/f for CSI). All resources gated with `count = var.ldap_dual_account ? 1 : 0`.
- `kubernetes_auth.tf` — `vault_auth_backend` type kubernetes at path "kubernetes", config with EKS host/CA cert. Four roles: `vso-role` (bound to SA `vso-auth`, for VSO), `ldap-app-role` (bound to SA `ldap-app-vault-auth`, for direct app polling), `vault-agent-app-role` (bound to SA `ldap-app-vault-agent`, for Vault Agent sidecar), `csi-app-role` (bound to SA `ldap-app-csi`, for CSI Driver). All have `ldap-static-read` policy, audience `vault`, token TTL 600s.
- `variables.tf` — `ldap_url`, `ldap_binddn`, `ldap_bindpass` (sensitive), `ldap_userdn`, `secrets_mount_path`, `active_directory_domain`, `static_role_name`, `static_role_username`, `static_role_rotation_period` (default 300), `kubernetes_host`, `kubernetes_ca_cert`, `kube_namespace`, `ad_user_job_completed`, `ldap_dual_account` (bool), `grace_period` (number), `dual_account_static_role_name`, `plugin_sha256`
- `outputs.tf` — `ldap_secrets_mount_path` (conditional for both modes), `ldap_secrets_mount_accessor`, `static_role_name` (conditional), `static_role_credentials_path`, `static_role_policy_name`, `vault_app_auth_role_name` (returns "ldap-app-role" when dual-account, "" otherwise)

#### `modules/ldap_app/` — Python App Deployments (3 delivery methods) + VSO Integration
**Providers:** kubernetes, time

**Files:**
- `ldap_app.tf` — VSO delivery: `VaultDynamicSecret` CR, K8s secret `ldap-credentials`, rolling restart, dual-account direct Vault polling SA, env vars, `kubernetes_deployment_v1.ldap_app` (2 replicas), `kubernetes_service_v1` (LoadBalancer). Uses `svc-rotate-a`/`svc-rotate-b`.
- `vault_agent_app.tf` — Vault Agent sidecar delivery: SA `ldap-app-vault-agent`, ConfigMap with Vault Agent HCL configs (Consul Template conditionals for dual-account standby_* fields during grace_period), projected SA token volume with `audience: "vault"`, init container + sidecar + app container, dual-account env vars (DUAL_ACCOUNT_MODE, VAULT_ADDR, LDAP_MOUNT_PATH=ldap, LDAP_STATIC_ROLE_NAME=vault-agent-dual-role), `kubernetes_service_v1` (LoadBalancer). Uses `svc-rotate-c`/`svc-rotate-d`.
- `csi_app.tf` — CSI Driver delivery: SA `ldap-app-csi`, `SecretProviderClass` with full JSON response object + per-field objects for `csi-dual-role`, projected SA token volume for direct Vault polling, dual-account env vars, deployment with CSI volume mount at `/vault/secrets`, `kubernetes_service_v1` (LoadBalancer). Uses `svc-rotate-e`/`svc-rotate-f`.
- `variables.tf` — `kube_namespace`, `ldap_mount_path`, `ldap_static_role_name`, `vso_vault_auth_name`, `static_role_rotation_period`, `ldap_app_image`, `ldap_dual_account` (bool), `grace_period` (number), `vault_app_auth_role` (string), `vault_agent_image` (string)

### Python Web Application (`python-app/`)

Flask app (`app.py`, APP_VERSION 3.0.0) displaying LDAP credentials in three delivery modes:

**VSO mode** (`SECRET_DELIVERY_METHOD=vault-secrets-operator`): Dual-account, polls Vault directly via `VaultClient` (hvac), timeline UI with Account A/B.

**Vault Agent sidecar mode** (`SECRET_DELIVERY_METHOD=vault-agent-sidecar`): Reads key=value file rendered by Vault Agent at `SECRETS_FILE_PATH`. Uses `FileCredentialCache` with 5s refresh.

**CSI Driver mode** (`SECRET_DELIVERY_METHOD=vault-csi-driver`): Reads individual files from CSI-mounted directory at `VAULT_CSI_SECRETS_DIR`. Uses `FileCredentialCache` with 5s refresh.

**Common:**
- `VaultClient` class: authenticates via K8s SA token to Vault K8s auth, hvac-based
- `FileCredentialCache`: background thread reads file-based creds every 5s
- HDS-styled UI with delivery method badge, live countdown timer
- Health check at `/health`, credentials API at `/api/credentials`
- `Dockerfile`: multi-stage build, python:3.11-slim, non-root UID 1000, port 8080
- `requirements.txt`: Flask==3.1.0, Werkzeug==3.1.3, requests==2.32.3, hvac==2.3.0
- Image: `ghcr.io/andybaran/vault-ldap-demo:latest`
- `VaultClient`: Authenticates via K8s service account token (`/var/run/secrets/kubernetes.io/serviceaccount/token`) to Vault K8s auth, caches token with 80% lease renewal, reads `GET /v1/<mount>/static-cred/<role>` on demand.
- `/api/credentials` JSON endpoint: Returns live data from Vault (active account, standby account during grace period, TTL, rotation state).
- Timeline UI: SVG-style horizontal rows for Account A / Account B with color-coded phases (Active=#B3D9FF blue, Grace=#FFFFCC yellow, Inactive=#FFB3B3 red), animated vertical marker tracking current position, credential cards, JS polls every 5s with 1s interpolation.
- Falls back to env vars if Vault polling fails.

**Common:**
- Health check at `/health`
- `Dockerfile`: multi-stage build, python:3.11-slim, non-root user (UID 1000), port 8080
- `requirements.txt`: Flask==3.1.0, Werkzeug==3.1.3, requests==2.32.3
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
- **AD Users managed by Vault:** svc-rotate-a through svc-rotate-f, svc-single, svc-lib (created by DC user_data)
- **App displays account:** svc-rotate-a by default (configurable via `ldap_app_account_name` stack variable)
- **LDAP bind DN:** CN=Administrator,CN=Users,DC=mydomain,DC=local
- **Vault dual-account static roles:**
  - `dual-rotation-demo` (svc-rotate-a/svc-rotate-b) → VSO delivery
  - `vault-agent-dual-role` (svc-rotate-c/svc-rotate-d) → Vault Agent sidecar delivery
  - `csi-dual-role` (svc-rotate-e/svc-rotate-f) → CSI Driver delivery
- **VSO auth role:** vso-role (bound to SA `vso-auth`)
- **App direct polling auth role:** ldap-app-role (bound to SA `ldap-app-vault-auth`, dual-account mode only)
- **Vault Agent auth role:** vault-agent-app-role (bound to SA `ldap-app-vault-agent`)
- **CSI auth role:** csi-app-role (bound to SA `ldap-app-csi`)
- **VSO VaultAuth/VaultConnection names:** "default"
- **Kubernetes auth path in Vault:** "kubernetes"
- **Rotation period:** 100s (set in `components.tfcomponent.hcl`)
- **Grace period:** 20s (set in `deployments.tfdeploy.hcl`, dual-account mode only)
- **Deployment region:** us-east-2
- **Customer name:** fidelity (truncated to 4 chars: "fide")
- **Instance type:** c5.xlarge (for deployment), t3.medium (default in module)
- **EKS AMI release:** 1.34.2-20260128
- **Dual-account mode:** `ldap_dual_account = true` in `deployments.tfdeploy.hcl`
- **Custom plugin image:** `ghcr.io/andybaran/vault-with-openldap-plugin:dual-account-rotation` (used when `ldap_dual_account=true`)
- **Plugin binary:** `/vault/plugins/vault-plugin-secrets-openldap` (SHA256: `e71b4bec10963fe5f704d710f34be5a933330126799541fd1bd7b0e3536a8dad`)
- **Plugin name in Vault catalog:** `ldap_dual_account`
- **Dual-account static roles:**
  - `dual-rotation-demo` (username=svc-rotate-a, username_b=svc-rotate-b) → VSO
  - `vault-agent-dual-role` (username=svc-rotate-c, username_b=svc-rotate-d) → Vault Agent
  - `csi-dual-role` (username=svc-rotate-e, username_b=svc-rotate-f) → CSI Driver

### Known Issues / Notes

1. **Vault root token exposed as nonsensitive** — `vault_root_token` output uses `nonsensitive()` wrapper. Acceptable for demo but noted.
2. **Terraform Stacks identity tracking** — `kubernetes_deployment_v1` can trigger "Unexpected Identity Change" errors on first apply after spec changes (provider returns real identity where nulls were stored). Transient; retry resolves it.
3. **Vault provider decoupled from vault_cluster outputs** — Vault provider uses `var.vault_address` and `var.vault_token` stored in varset `varset-fMrcJCnqUd6q4D9C` to avoid Stacks unknown-output dependency problem.
4. **Vault Agent requires projected SA token** — Vault Agent kubernetes auto_auth does NOT support `token_audiences`. Must project a K8s SA token with `audience: "vault"` as a volume and set `token_path` to the projected token path.

#### Resolved (V2 PRs #184-#189)
- V2 multi-delivery refactoring complete: VSO, Vault Agent sidecar, CSI Driver all deployed and verified
- Python app refactored to hvac + FileCredentialCache for file-based delivery methods
- 22 pytest tests added, 5 documentation files created

#### Resolved (PR #174)
- ~~Grace period countdown always shows 0~~ — Root cause: VSO refresh cycle + pod restart exceeded grace period. Fixed by switching to direct Vault API polling from the app (PRs #172-#174).

#### Resolved (PRs #164-#168)
- ~~Dual-account LDAP rotation~~ — Implemented optional blue/green credential rotation using custom Vault plugin `ldap_dual_account`.

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
