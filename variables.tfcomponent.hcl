variable "customer_name" {
  description = "Specify the name of your customer. This helps to customize the resources created for your customer."
  type        = string
}


variable "region" {
  description = "The AWS region to use for this demo."
  type        = string
  default     = "us-east-2"
}

variable "instance_type" {
  description = "The EC2 instance type to use for the EKS worker nodes."
  type        = string
  default     = "t2.medium"
}

variable "vault_public_endpoint" {
  type    = string
  default = ""
}

variable "vault_root_namespace" {
  type    = string
  default = ""
}

variable "user_email" {
  type    = string
  default = ""
}

variable "AWS_ACCESS_KEY_ID" {
  description = "AWS access key"
  type        = string
  ephemeral   = true
}

variable "AWS_SECRET_ACCESS_KEY" {
  description = "AWS sensitive secret key."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "AWS_SESSION_TOKEN" {
  description = "AWS session token."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "vault_license_key" {
  description = "The Vault Enterprise license key."
  type        = string
  sensitive   = false
}

variable "eks_node_ami_release_version" {
  description = "EKS managed node group AMI release version"
  type        = string
}

variable "allowlist_ip" {
  description = "IP CIDR to allow RDP/Kerberos access to the domain controller (e.g., '1.2.3.4/32')"
  type        = string
  default     = "0.0.0.0/0"
}

variable "vault_image" {
  description = "Docker image for Vault Enterprise (repository:tag)"
  type        = string
  default     = "hashicorp/vault-enterprise:1.21.2-ent"
}

variable "ldap_app_image" {
  description = "Docker image for the LDAP credentials display application"
  type        = string
  default     = "ghcr.io/andybaran/vault-ldap-demo:latest"
}

variable "ldap_app_account_name" {
  description = "AD service account name to display in the LDAP app (must exist in static_roles)"
  type        = string
  default     = "svc-rotate-a"
}

variable "ldap_dual_account" {
  description = "Enable dual-account (blue/green) LDAP rotation using a custom Vault plugin. When true, uses a custom Vault image with the plugin and configures dual-account static roles."
  type        = bool
  default     = false
}

variable "grace_period" {
  description = "Grace period in seconds for dual-account rotation (both credentials valid during this window). Must be less than rotation period."
  type        = number
  default     = 20
}

variable "full_ui" {
  description = "When true, the domain controller is provisioned with the AWS Windows Server 2025 Desktop Experience AMI (full Windows GUI) instead of the hc-base Server Core AMI. Useful for remote administration via RDP. Defaults to false to minimize cost and preserve hc-base CISO hardening."
  type        = bool
  default     = false
}

variable "install_adds" {
  description = "When true (default), the domain controller installs AD Domain Services and promotes to a domain controller. Set to false to provision a plain Windows Server without any AD role."
  type        = bool
  default     = true
}

variable "install_adcs" {
  description = "When true (default), installs AD Certificate Services on the domain controller to enable LDAPS on port 636. Requires install_adds=true. Set to false to skip ADCS — Vault must then use ldap:// instead of ldaps://."
  type        = bool
  default     = true
}

variable "ldap_provider" {
  description = "Which LDAP backend to deploy: 'ad' for the Windows Active Directory domain controller (AWS_DC module) or 'openldap' for an OpenLDAP server running on EKS. The custom dual-account Vault plugin works with both."
  type        = string
  default     = "openldap"
}

variable "openldap_domain" {
  description = "LDAP domain for OpenLDAP (e.g., 'demo.hashicorp'). Converted to base DN dc=demo,dc=hashicorp."
  type        = string
  default     = "demo.hashicorp"
}

variable "openldap_admin_password" {
  description = "Admin password for the OpenLDAP server. Used as the bind password for Vault."
  type        = string
  sensitive   = true
  default     = "VaultDemo2026!"
}

