variable "kube_namespace" {
  description = "Kubernetes namespace where OpenLDAP will be deployed"
  type        = string
  default     = "default"
}

variable "openldap_domain" {
  description = "LDAP domain (e.g., 'demo.hashicorp'). Converted to base DN dc=demo,dc=hashicorp"
  type        = string
  default     = "demo.hashicorp"
}

variable "openldap_admin_password" {
  description = "Admin password for the OpenLDAP server"
  type        = string
  sensitive   = true
  default     = "VaultDemo2026!"
}

variable "prefix" {
  description = "Resource name prefix"
  type        = string
  default     = "vault-demo"
}

variable "enabled" {
  description = "When true, creates the OpenLDAP deployment on EKS. Set to false to skip."
  type        = bool
  default     = true
}
