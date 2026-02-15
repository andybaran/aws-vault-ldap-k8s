variable "kube_namespace" {
  description = "The Kubernetes namespace for the application."
  type        = string
}

variable "vault_image" {
  description = "Docker image for Vault Enterprise (repository:tag)"
  type        = string
  default     = "hashicorp/vault-enterprise:1.21.2-ent"
}

locals {
  # Split the vault_image into repository and tag for Helm values
  vault_image_parts = split(":", var.vault_image)
  vault_repository  = local.vault_image_parts[0]
  vault_tag         = length(local.vault_image_parts) > 1 ? local.vault_image_parts[1] : "latest"
}