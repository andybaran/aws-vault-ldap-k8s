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