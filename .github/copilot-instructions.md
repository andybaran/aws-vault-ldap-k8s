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

## Multi-Agent Workflow

This project uses a multi-agent orchestration pattern where specialized agents collaborate to manage different aspects of the infrastructure and application development lifecycle. All agents must report their status to a centralized dashboard for coordination and monitoring.

### Agent Status Dashboard Integration

The agent status dashboard provides real-time visibility into agent activities and coordinates work across the team. The dashboard runs at a configurable URL (default: `http://localhost:5050`, but may vary per session/environment).

**API Reference:**
- **Endpoint:** `POST /api/update/<agent_name>/<status>`
- **Valid Statuses:** `working`, `waiting`, `completed`, `idle`, `blocked`, `error`
- **Optional Query Parameters:**
  - `task` — Task name or description (URL-encoded)
  - `task_url` — Link to GitHub issue or PR (URL-encoded)

**Example Status Updates:**
```bash
# Report starting work on a task
curl -s -X POST "http://localhost:5050/api/update/Terraform%20Agent/working?task=Update%20vault%20module" > /dev/null

# Report waiting for another agent
curl -s -X POST "http://localhost:5050/api/update/Python%20Agent/waiting?task=Waiting%20for%20Research%20Agent" > /dev/null

# Report task completion with GitHub issue link
curl -s -X POST "http://localhost:5050/api/update/Testing%20Agent/completed?task=Validate%20rotation&task_url=https://github.com/andybaran/aws-vault-ldap-k8s/issues/123" > /dev/null

# Report error state
curl -s -X POST "http://localhost:5050/api/update/Terraform%20Deploy%20Agent/error?task=Deployment%20failed" > /dev/null
```

**Naming Convention:**
- Use Title Case with spaces for agent names (e.g., "Python Agent", "Terraform Agent")
- URL-encode agent names in API calls (spaces become `%20`)
- Keep agent names consistent across all status updates
- Examples: `Python%20Agent`, `Kubernetes%20Agent`, `UI%20Agent`, `Documentation%20Agent`

**Status Lifecycle:**
1. Agent reports `working` when starting a task
2. Agent reports `waiting` if blocked on another agent or human approval
3. Agent reports `completed` when task finishes successfully
4. Agent reports `error` if task fails
5. Agent reports `idle` when available for new work
6. **Stale Threshold:** Agents not reporting for 30+ minutes are considered stale

### Agent Definitions

| Agent Name | Responsibility |
|---|---|
| Python Agent | Refactor python-app/ Flask application, write pytest tests, use hvac library |
| Kubernetes Agent | Create/modify K8s resources (deployments, services, ConfigMaps), manage Vault Agent sidecar/CSI/VSO manifests |
| UI Agent | Update Python app UI (HDS-styled templates), timeline visualization, delivery method badges |
| Documentation Agent | Update README.md, v2-instructions.md, copilot-instructions.md, module READMEs |
| Testing Agent | Validate deployments, run pytest, integration testing, verify credential rotation |
| Terraform Agent | Update HCL modules (kube0, kube1, vault, vault_ldap_secrets, ldap_app, AWS_DC), manage providers, stack components |
| Research Agent | Research Terraform providers/modules, Vault APIs, AWS services, EKS features, inform other agents |
| Terraform Deploy Agent | Deploy via HCP Terraform (org: andybaran, stack: aws-vault-ldap-k8s), monitor runs, troubleshoot failures |
| GitOps Agent | Coordinate branches, PRs, code reviews, merge orchestration, resolve conflicts |
| Time Tracking Agent | Monitor agent status dashboard, report anomalies, ensure all agents report correctly |

#### Python Agent

The Python Agent owns the Flask application codebase located in `python-app/`. It is responsible for implementing credential delivery methods (VSO, Vault Agent sidecar, CSI Driver), integrating the hvac library for direct Vault API communication, and writing pytest tests to validate application behavior.

**Primary Files:**
- `python-app/app.py` — Main Flask application (APP_VERSION 3.0.0)
- `python-app/requirements.txt` — Python dependencies (Flask, hvac, requests)
- `python-app/Dockerfile` — Multi-stage Docker build
- `python-app/tests/` — pytest test suite

**Coordinates With:**
- **UI Agent** — Provides backend endpoints and data structures for frontend rendering
- **Kubernetes Agent** — Validates K8s deployment manifests match application requirements
- **Testing Agent** — Ensures pytest tests cover all credential delivery methods
- **Research Agent** — Consults on hvac library best practices and Vault API usage

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/Python%20Agent/working?task=Implement%20CSI%20Driver%20support&task_url=https://github.com/andybaran/aws-vault-ldap-k8s/issues/185" > /dev/null
```

#### Kubernetes Agent

The Kubernetes Agent manages all Kubernetes manifests and resources across the project. It creates and modifies K8s deployments, services, ConfigMaps, ServiceAccounts, and custom resources (VaultDynamicSecret, SecretProviderClass). It is the expert on Vault Agent sidecar injection, VSO integration, and CSI Driver configuration.

**Primary Files:**
- `modules/kube1/2_kube_tools.tf` — Vault ServiceAccount, nginx ingress, Vault license secret
- `modules/vault/vso.tf` — VaultConnection, VaultAuth CRs
- `modules/vault/vault.tf` — Vault Helm chart configuration
- `modules/ldap_app/ldap_app.tf` — VSO VaultDynamicSecret, app deployment
- `modules/ldap_app/vault_agent_app.tf` — Vault Agent sidecar manifests
- `modules/ldap_app/csi_app.tf` — CSI Driver SecretProviderClass

**Coordinates With:**
- **Python Agent** — Ensures K8s manifests expose correct env vars and volume mounts
- **Terraform Agent** — Validates HCL kubernetes_* resources align with K8s best practices
- **Testing Agent** — Provides deployment status for integration tests
- **Vault LDAP Secrets Agent** (conceptual) — Validates VaultAuth roles and policies

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/Kubernetes%20Agent/completed?task=Add%20CSI%20SecretProviderClass&task_url=https://github.com/andybaran/aws-vault-ldap-k8s/pull/189" > /dev/null
```

#### UI Agent

The UI Agent owns the frontend presentation layer of the Python Flask application. It implements HDS (Helios Design System)-styled templates, creates timeline visualizations showing dual-account credential rotation phases, and designs delivery method badges to distinguish between VSO, Vault Agent, and CSI Driver modes.

**Primary Files:**
- `python-app/templates/` — Jinja2 HTML templates
- `python-app/static/` — CSS, JavaScript assets
- `python-app/app.py` — Template rendering logic (`/`, `/api/credentials` endpoints)

**Coordinates With:**
- **Python Agent** — Consumes JSON API data from `/api/credentials` endpoint
- **Documentation Agent** — Ensures UI screenshots in README.md are current
- **Testing Agent** — Validates UI renders correctly for all delivery methods

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/UI%20Agent/working?task=Refactor%20timeline%20SVG%20animation" > /dev/null
```

#### Documentation Agent

The Documentation Agent maintains all project documentation, ensuring it stays synchronized with code changes. It updates README files, architecture diagrams, module descriptions, and the authoritative Codebase Snapshot in `.github/copilot-instructions.md`.

**Primary Files:**
- `README.md` — Project overview, deployment instructions
- `v2-instructions.md` — V2 multi-delivery refactoring guide
- `.github/copilot-instructions.md` — This file, agent instructions and codebase snapshot
- `modules/*/README.md` — Module-specific documentation
- `python-app/README.md` — Application documentation

**Coordinates With:**
- **All Agents** — Documents changes from every agent's work
- **GitOps Agent** — Ensures PRs include documentation updates
- **Testing Agent** — Documents test coverage and validation procedures

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/Documentation%20Agent/completed?task=Update%20Codebase%20Snapshot%20for%20PR%20189" > /dev/null
```

#### Testing Agent

The Testing Agent validates that deployments work correctly, runs pytest test suites, performs integration testing across AWS/EKS/Vault components, and verifies credential rotation behavior. It ensures all three delivery methods (VSO, Vault Agent, CSI) function as expected.

**Primary Files:**
- `python-app/tests/` — pytest test suite (22 tests covering all delivery methods)
- `modules/vault/vault_init.tf` — Vault initialization job (integration test target)
- `modules/ldap_app/` — All three app deployment manifests (test targets)

**Coordinates With:**
- **Python Agent** — Runs pytest tests after code changes
- **Kubernetes Agent** — Validates K8s resource deployments succeeded
- **Terraform Deploy Agent** — Tests infrastructure after Terraform apply
- **Research Agent** — Consults on testing best practices for Vault/K8s integration

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/Testing%20Agent/working?task=Validate%20dual-account%20rotation&task_url=https://github.com/andybaran/aws-vault-ldap-k8s/issues/172" > /dev/null
```

#### Terraform Agent

The Terraform Agent is the HCL expert, managing all Terraform modules, stack components, provider configurations, and variable declarations. It ensures modules follow best practices, updates provider versions, and maintains the dependency graph across the 5 stack components (kube0, kube1, vault_cluster, vault_ldap_secrets, ldap_app, ldap).

**Primary Files:**
- `components.tfcomponent.hcl` — Stack component definitions and wiring
- `deployments.tfdeploy.hcl` — Deployment configuration (development in us-east-2)
- `providers.tfcomponent.hcl` — Provider version pinning
- `variables.tfcomponent.hcl` — Stack variable declarations
- `modules/kube0/` — VPC, EKS cluster, security groups
- `modules/kube1/` — Kubernetes base tools (nginx, Vault SA)
- `modules/vault/` — Vault Helm chart, init job, VSO
- `modules/vault_ldap_secrets/` — LDAP secrets engine, K8s auth backend
- `modules/ldap_app/` — Python app deployments (VSO, Agent, CSI)
- `modules/AWS_DC/` — Active Directory domain controller

**Coordinates With:**
- **Research Agent** — Consults on latest Terraform provider/module versions
- **Kubernetes Agent** — Ensures kubernetes_* resources are idiomatic
- **Terraform Deploy Agent** — Validates HCL changes before deployment
- **Documentation Agent** — Updates module READMEs after changes

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/Terraform%20Agent/working?task=Add%20grace_period%20variable&task_url=https://github.com/andybaran/aws-vault-ldap-k8s/issues/165" > /dev/null
```

#### Research Agent

The Research Agent is the knowledge expert, conducting research on Terraform providers/modules, Vault APIs, AWS services, EKS features, and best practices. It does NOT implement changes directly—instead, it informs other agents with findings, recommendations, and authoritative documentation links. It runs FIRST in the workflow to provide guidance before other agents begin work.

**Primary Tools:**
- Terraform MCP server (`search_providers`, `search_modules`, `get_latest_provider_version`)
- Vault skill/documentation
- AWS skill/documentation
- Web search for HashiCorp/AWS official docs

**Coordinates With:**
- **All Agents** — Provides research findings to inform their work
- **Terraform Agent** — Recommends provider/module versions and best practices
- **Python Agent** — Researches hvac library APIs and Vault endpoint schemas
- **Kubernetes Agent** — Researches VSO/CSI/Vault Agent integration patterns

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/Research%20Agent/completed?task=Research%20Vault%20dual-account%20plugin%20APIs" > /dev/null
```

#### Terraform Deploy Agent

The Terraform Deploy Agent manages deployments via HCP Terraform (organization: `andybaran`, stack: `aws-vault-ldap-k8s`). It monitors Terraform runs, troubleshoots apply failures, and coordinates deployment timing with other agents. It does NOT write Terraform code—it deploys changes made by the Terraform Agent.

**Primary Tools:**
- Terraform MCP server (`create_run`, `get_run_details`, `list_runs`, `get_workspace_details`)
- HCP Terraform API for stack operations
- GitHub CLI for coordinating with GitOps Agent

**Coordinates With:**
- **Terraform Agent** — Deploys HCL changes after code review
- **GitOps Agent** — Waits for PR approval before deploying to main branch
- **Testing Agent** — Triggers validation tests after successful deployment
- **Time Tracking Agent** — Reports long-running deployments

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/Terraform%20Deploy%20Agent/waiting?task=Waiting%20for%20PR%20approval%20before%20deploy" > /dev/null
```

#### GitOps Agent

The GitOps Agent coordinates Git workflows, including branch creation, pull requests, code reviews, merge orchestration, and conflict resolution. It ensures all PRs target the `main` branch, enforces human approval requirements, and manages parallel work across multiple feature branches.

**Primary Tools:**
- `git` CLI for branch/commit operations
- `gh` CLI for GitHub PR/issue management
- GitHub MCP server for advanced PR operations

**Coordinates With:**
- **All Agents** — Creates branches and PRs for their work
- **Documentation Agent** — Ensures PRs include documentation updates
- **Testing Agent** — Requires test validation before merge
- **Terraform Deploy Agent** — Coordinates deployment timing with merges

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/GitOps%20Agent/working?task=Create%20PR%20for%20CSI%20integration&task_url=https://github.com/andybaran/aws-vault-ldap-k8s/pull/189" > /dev/null
```

#### Time Tracking Agent

The Time Tracking Agent monitors the agent status dashboard, detects stale agents (no updates for 30+ minutes), reports anomalies, and ensures all agents comply with status reporting requirements. It acts as a meta-monitor, keeping the multi-agent system healthy and coordinated.

**Primary Responsibilities:**
- Poll dashboard API to detect stale agents
- Alert when agents report `error` or `blocked` status
- Validate agents report status during their lifecycle
- Generate summary reports of agent activity

**Coordinates With:**
- **All Agents** — Monitors their status updates
- **GitOps Agent** — Reports on PR/merge bottlenecks
- **Terraform Deploy Agent** — Alerts on long-running deployments

**Status Reporting Example:**
```bash
curl -s -X POST "http://localhost:5050/api/update/Time%20Tracking%20Agent/working?task=Monitor%20agent%20health" > /dev/null
```

### Orchestration Rules

1. **Research Agent runs first:** Before starting work on a new feature or issue, the Research Agent should investigate best practices, provider versions, and API schemas to inform other agents.

2. **Maximize parallel work:** Agents should work on independent tasks simultaneously whenever possible. Use GitHub issues to track parallel work streams. Example: Python Agent refactors app logic while Terraform Agent updates module HCL.

3. **Human approval for main branch:** All pull requests targeting `main` must be reviewed and approved by a human before merging. Agents should report `waiting` status when blocked on PR approval.

4. **Report `waiting` when blocked:** If an agent is blocked on another agent's work, it must report `waiting` status with a clear description. Example: "Waiting for Terraform Agent to update vault module" or "Waiting for PR #189 approval".

5. **Use task metadata:** When working on GitHub issues, always include `task` (issue title) and `task_url` (issue link) in status updates for traceability.

6. **Stale agent recovery:** If an agent becomes stale (30+ min without update), the Time Tracking Agent should alert and another agent may resume the work.

7. **Error escalation:** Agents reporting `error` status should include diagnostic information in the `task` parameter and coordinate with other agents for resolution.

8. **Deployment coordination:** Terraform Deploy Agent should only deploy after Terraform Agent has completed HCL changes, GitOps Agent has created a PR, and Testing Agent has validated changes in a branch deployment.

9. **Documentation is mandatory:** Documentation Agent must update `.github/copilot-instructions.md` Codebase Snapshot section for every PR that changes architecture, modules, or dependencies.

10. **Branch strategy:** Create feature branches from `main`, name them descriptively (e.g., `feature/csi-driver-integration`, `fix/vault-init-idempotency`), and always target `main` for PRs. Never commit directly to `main`.

## Maintaining This Document

**IMPORTANT:** When creating PRs, update the "Codebase Snapshot" section below to reflect any changes you made. This keeps future sessions from needing to re-read the entire codebase. Specifically update:
- File lists if files were added, removed, or renamed
- Module descriptions if behavior or interfaces changed
- Provider versions if bumped
- Dependency graph if component wiring changed
- Any new outputs, variables, or resources relevant to understanding the architecture

---

## Codebase Snapshot (last updated: 2026-03-02, post Windows cleanup + DC AMI upgrade)

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
  └──► ldap (Windows EC2 domain controller, AD forest, AD CS for LDAPS)
```

### Module Details

#### `modules/kube0/` — VPC, EKS Cluster, Security Groups
**Providers:** aws, random, tls, null, time, cloudinit

**Files:**
- `1_locals.tf` — Naming locals (`customer_id`, `demo_id`, `resources_prefix`), AZ selection (filters AZs supporting the requested instance type, picks up to 3), `random_string.identifier`
- `1_aws_network.tf` — VPC module (`terraform-aws-modules/vpc/aws` v6.5.1), CIDR `10.0.0.0/16`, single NAT gateway, public/private subnets with ELB tags
- `1_aws_eks.tf` — EKS module (`terraform-aws-modules/eks/aws` v21.11.0), K8s 1.34, public endpoint, `enable_cluster_creator_admin_permissions=true`, addons (coredns, eks-pod-identity-agent, kube-proxy, vpc-cni, aws-ebs-csi-driver), managed node group: `linux_nodes` (1-3, desired 3). EBS CSI driver IAM role with IRSA.
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
- `main.tf` — Windows Server 2025 EC2 (`data.aws_ami.hc_base_windows_server_2025`, owner `888995627335` security-approved AMI), RSA-4096 keypair for RDP, security group (RDP + Kerberos from allowlist_ip), DSRM password via `random_string`, `random_password.test_user_password` (for_each over 8 test accounts), user_data PowerShell: first boot promotes to DC (`Install-ADDSForest`, domain `mydomain.local`), second boot installs AD CS (`Install-AdcsCertificationAuthority` for LDAPS) and creates test service accounts (svc-rotate-a through svc-rotate-f, svc-single, svc-lib). Elastic IP attached. **`time_sleep.wait_for_dc_reboot` (10m) ensures reboot cycle completes before outputs become available.**
- `variables.tf` — `allowlist_ip`, `prefix` (default "boundary-rdp"), `aws_key_pair_name`, `ami` (unused default), `domain_controller_instance_type`, `root_block_device_size` (128GB), `active_directory_domain` (mydomain.local), `active_directory_netbios_name` (mydomain), `only_ntlmv2`, `only_kerberos`, `vpc_id`, `subnet_id`, `shared_internal_sg_id`
- `outputs.tf` — `private-key`, `public-dns-address`, `eip-public-ip`, `dc-priv-ip`, `password` (decrypted admin pw, nonsensitive), `aws_keypair_name`, `static_roles` (map of test account username/password/dn from `random_password`). **All outputs depend on `time_sleep.wait_for_dc_reboot`.**
- `README.md` — Documents the DC setup and PowerShell user_data

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

### CI/CD (`.github/workflows/`)

| Workflow | Trigger | Image |
|----------|---------|-------|
| `build-python-app-image.yml` | push to `main` on `python-app/**` | `ghcr.io/andybaran/vault-ldap-demo` |

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
