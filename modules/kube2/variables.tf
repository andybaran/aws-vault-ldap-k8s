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