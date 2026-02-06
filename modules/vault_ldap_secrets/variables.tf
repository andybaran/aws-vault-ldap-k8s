variable "ldap_url" {
  description = "LDAP server URL (e.g., ldap://10.0.0.5)"
  type        = string
}

variable "ldap_binddn" {
  description = "Distinguished name for Vault's service account to bind to LDAP"
  type        = string
  default     = "CN=Administrator,CN=Users,DC=mydomain,DC=local"
}

variable "ldap_bindpass" {
  description = "Password for the LDAP bind account"
  type        = string
  sensitive   = true
}

variable "ldap_userdn" {
  description = "Base DN under which to perform user search"
  type        = string
  default     = "CN=Users,DC=mydomain,DC=local"
}

variable "secrets_mount_path" {
  description = "Path where the LDAP secrets engine will be mounted"
  type        = string
  default     = "ldap"
}

variable "active_directory_domain" {
  description = "The Active Directory domain name"
  type        = string
  default     = "mydomain.local"
}

variable "static_role_name" {
  description = "Name of the static role for password rotation"
  type        = string
  default     = "demo-service-account"
}

variable "static_role_username" {
  description = "AD username for the static role (without domain)"
  type        = string
  default     = "vault-demo"
}

variable "static_role_rotation_period" {
  description = "Password rotation period in seconds (default: 24 hours)"
  type        = number
  default     = 86400
}

variable "kubernetes_host" {
  description = "Kubernetes API server URL for Vault auth backend"
  type        = string
}

variable "kubernetes_ca_cert" {
  description = "Kubernetes cluster CA certificate (base64 encoded) for Vault auth backend"
  type        = string
}

variable "kube_namespace" {
  description = "Kubernetes namespace where VSO is deployed"
  type        = string
}

variable "ad_user_job_completed" {
  description = "Dependency marker to ensure AD user creation job completes before Vault LDAP secrets engine configuration"
  type        = string
}
