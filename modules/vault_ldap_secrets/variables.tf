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
