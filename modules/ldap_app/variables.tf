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

variable "rotation_period" {
  description = "LDAP static role rotation period in seconds"
  type        = number
  default     = 10
}