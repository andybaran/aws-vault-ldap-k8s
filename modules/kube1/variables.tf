variable "demo_id" {
  description = "demo id"
  type        = string
}

variable "cluster_endpoint" {
  description = "The endpoint for the EKS cluster."
  type        = string
}

variable "kube_cluster_certificate_authority_data" {
  description = "Kube cluster CA data"
  type        = string
}

variable "vault_license_key" {
  description = "The Vault Enterprise license key."
  type        = string
  sensitive   = false
}
