variable "kube_namespace" {
  description = "The Kubernetes namespace for the application."
  type        = string
}

# variable "vault_license_key" {
#   description = "The Vault Enterprise license key."
#   type        = string
#   sensitive = false 
# }