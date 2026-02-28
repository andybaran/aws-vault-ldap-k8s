variable "kube_namespace" {
  description = "The Kubernetes namespace to deploy resources into."
  type        = string
  default     = "default"
}

variable "ldap_mount_path" {
  description = "The Vault LDAP secrets engine mount path"
  type        = string
  default     = "ldap"
}

variable "ldap_static_role_name" {
  description = "The name of the LDAP static role in Vault"
  type        = string
  default     = "demo-service-account"
}

variable "vso_vault_auth_name" {
  description = "The name of the VaultAuth resource created by VSO"
  type        = string
  default     = "default"
}

variable "static_role_rotation_period" {
  description = "The LDAP static role rotation period in seconds. Used to derive the VSO refreshAfter interval."
  type        = number
  default     = 30
}

variable "ldap_app_image" {
  description = "Docker image for the LDAP credentials display application"
  type        = string
  default     = "ghcr.io/andybaran/vault-ldap-demo:latest"
}

variable "ldap_dual_account" {
  description = "Enable dual-account (blue/green) LDAP rotation display in the app"
  type        = bool
  default     = false
}

variable "grace_period" {
  description = "Grace period in seconds for dual-account rotation"
  type        = number
  default     = 15
}

variable "vault_app_auth_role" {
  description = "Vault K8s auth role name for the app to authenticate directly"
  type        = string
  default     = ""
}

variable "vault_agent_image" {
  description = "Docker image for Vault Agent sidecar"
  type        = string
  default     = "hashicorp/vault:1.18.0"
}