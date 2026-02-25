variable "kube_namespace" {
  description = "The Kubernetes namespace for the application."
  type        = string
}

variable "vault_image" {
  description = "Docker image for Vault Enterprise (repository:tag)"
  type        = string
  default     = "hashicorp/vault-enterprise:1.21.2-ent"
}

variable "ldap_dual_account" {
  description = "Enable dual-account LDAP rotation. When true, configures plugin_directory in Vault for custom plugin support."
  type        = bool
  default     = false
}

locals {
  # Split the vault_image into repository and tag for Helm values
  vault_image_parts = split(":", var.vault_image)
  vault_repository  = local.vault_image_parts[0]
  vault_tag         = length(local.vault_image_parts) > 1 ? local.vault_image_parts[1] : "latest"
}