# output "vault_unseal_keys" {
#   description = "Vault unseal keys (base64 encoded)"
#   value       = local.unseal_keys_b64
#   sensitive   = true
# }

# output "vault_root_token" {
#   description = "Vault root token"
#   value       = local.root_token
#   sensitive   = true
# }

output "vault_namespace" {
  description = "Kubernetes namespace where Vault is deployed"
  value       = var.kube_namespace
}

output "vault_service_name" {
  description = "Vault service name"
  value       = "vault"
}

output "vault_initialized" {
  description = "Indicates if Vault has been initialized"
  value       = true
  depends_on  = [kubernetes_job_v1.vault_init]
}
