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

variable "static_roles" {
  description = "Map of static roles to create. Each key is the role name, value has username, password, and dn."
  type = map(object({
    username = string
    password = string
    dn       = string
  }))
}

variable "static_role_rotation_period" {
  description = "Password rotation period in seconds (default: 24 hours)"
  type        = number
  default     = 300
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

variable "ldap_dual_account" {
  description = "Enable dual-account (blue/green) LDAP rotation using a custom Vault plugin"
  type        = bool
  default     = false
}

variable "grace_period" {
  description = "Grace period in seconds for dual-account rotation"
  type        = number
  default     = 15
}

variable "dual_account_static_role_name" {
  description = "Name for the dual-account static role"
  type        = string
  default     = "dual-rotation-demo"
}

variable "plugin_sha256" {
  description = "SHA256 hash of the custom Vault plugin binary"
  type        = string
  default     = "e71b4bec10963fe5f704d710f34be5a933330126799541fd1bd7b0e3536a8dad"
}
