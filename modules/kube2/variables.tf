variable "kube_namespace" {
  description = "The Kubernetes namespace to deploy resources into."
  type        = string
  default     = "default"
}

variable "vault_mount_credentials_path" {
  description = "The Vault mount path for the credentials KV store."
  type        = string
  default     = ""
}