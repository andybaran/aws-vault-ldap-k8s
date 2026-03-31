# Module: AWS_DC — Active Directory Domain Controller

Provisions a Windows Server 2025 EC2 instance and promotes it to an Active Directory Domain Controller for `mydomain.local`. On the second boot (post-promotion) it optionally installs AD Certificate Services (enabling LDAPS on port 636) and creates the test service accounts that Vault will manage.

## AMI Selection

By default the module uses a **security-approved Windows Server 2025 Server Core AMI** maintained by an internal AMI pipeline (owner `888995627335`, filter `hc-base-windows-server-2025-x64-*`, always most-recent).

Set `full_ui = true` to use the Amazon-published **Windows Server 2025 Desktop Experience** AMI instead. This provides a full Windows GUI accessible via RDP and is useful for administration tasks. Provisioning time is not significantly affected.

## Two-Boot Provisioning Process

The `user_data` PowerShell script detects which boot it is on by checking whether the NTDS service is running:

**Boot 1 — Domain Controller promotion** (`install_adds = true`)
1. Installs the `AD-Domain-Services` Windows feature
2. Adds Windows Defender exclusions for `C:\Windows\NTDS` and `C:\Windows\SYSVOL` to prevent file-locking during promotion
3. Runs `Install-ADDSForest` with `DomainMode WinThreshold` / `ForestMode WinThreshold` (compatible with Windows Server 2025)
4. Instance reboots automatically after promotion

**Boot 2 — Post-promotion setup** (runs after reboot)
1. Installs AD Certificate Services (`ADCS-Cert-Authority`) and configures an Enterprise Root CA — enables LDAPS on port 636 (`install_adcs = true`)
2. Waits for Active Directory Web Services (ADWS) to be ready
3. Creates 8 test service accounts (initial passwords managed by Terraform):

| Account | Purpose |
|---------|---------|
| `svc-rotate-a` | VSO dual-account role — Account A |
| `svc-rotate-b` | VSO dual-account role — Account B |
| `svc-rotate-c` | Vault Agent dual-account role — Account A |
| `svc-rotate-d` | Vault Agent dual-account role — Account B |
| `svc-rotate-e` | CSI Driver dual-account role — Account A |
| `svc-rotate-f` | CSI Driver dual-account role — Account B |
| `svc-single` | Single-account static role example |
| `svc-lib` | Library/shared account example |

A `time_sleep` resource delays downstream outputs until the full two-boot cycle completes:

| Configuration | Wait Duration |
|---------------|--------------|
| `install_adds = false` | 3 minutes |
| `install_adds = true`, `install_adcs = false` | 7 minutes |
| `install_adds = true`, `install_adcs = true` (default) | 10 minutes |

## Additional Infrastructure

- **SSM access** — An IAM role with `AmazonSSMManagedInstanceCore` is attached to the instance for remote diagnostic sessions without requiring RDP or a bastion host.
- **Elastic IP** — A static public IP is allocated and attached so the DC address is stable across reboots.
- **DSRM password** — A random 8-character string (letters + digits + `.`) is generated for Safe Mode recovery.

## Input Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `allowlist_ip` | string | _(required)_ | CIDR block allowed for RDP (port 3389) and Kerberos (port 88) |
| `vpc_id` | string | _(required)_ | VPC ID where the DC will be deployed |
| `subnet_id` | string | _(required)_ | Public subnet ID for the DC EC2 instance |
| `shared_internal_sg_id` | string | _(required)_ | Security group for intra-VPC communication (from `kube0`) |
| `prefix` | string | `"boundary-rdp"` | Prefix for resource names (key pair, security group, EIP) |
| `aws_key_pair_name` | string | `"RDPKey"` | Suffix for the AWS key pair name |
| `domain_controller_instance_type` | string | `"m7i-flex.xlarge"` | EC2 instance type for the DC |
| `root_block_device_size` | string | `128` | Root EBS volume size in GiB |
| `active_directory_domain` | string | `"mydomain.local"` | AD domain DNS name |
| `active_directory_netbios_name` | string | `"mydomain"` | AD NetBIOS name |
| `only_ntlmv2` | bool | `false` | Restrict to NTLMv2 authentication only |
| `only_kerberos` | bool | `false` | Restrict to Kerberos authentication only |
| `full_ui` | bool | `false` | Use Windows Server 2025 Desktop Experience AMI (full GUI) instead of Server Core |
| `install_adds` | bool | `true` | Install AD Domain Services and promote to DC |
| `install_adcs` | bool | `true` | Install AD Certificate Services (enables LDAPS on port 636) |
| `ami` | string | _(unused)_ | Legacy variable; AMI is selected automatically via `data.aws_ami` |

## Outputs

All outputs depend on `time_sleep.wait_for_dc_reboot` and are only available after the full two-boot cycle.

| Output | Description |
|--------|-------------|
| `private-key` | RSA-4096 private key (PEM) for decrypting the Windows admin password — **not secure; demo only** |
| `public-dns-address` | Public DNS name of the Elastic IP |
| `eip-public-ip` | Public IP address of the Elastic IP |
| `dc-priv-ip` | Private IP address of the DC (used by Vault for LDAPS connection) |
| `password` | Decrypted Administrator password — **non-sensitive wrapper; demo only** |
| `aws_keypair_name` | Name of the created AWS key pair |
| `static_roles` | Map of `{ username, password, dn }` for all 8 test service accounts — passed to `vault_ldap_secrets` as `static_roles` input |
