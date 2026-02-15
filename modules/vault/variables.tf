variable "kube_namespace" {
  description = "The Kubernetes namespace for the application."
  type        = string
}

variable "vault_image_repository" {
  description = "Docker image repository for Vault Enterprise"
  type        = string
  default     = "hashicorp/vault-enterprise"
}

variable "vault_image_tag" {
  description = "Docker image tag for Vault Enterprise"
  type        = string
  default     = "1.21.2-ent"
}