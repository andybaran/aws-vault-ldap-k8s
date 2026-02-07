# Outputs for windows_config module

output "windows_ipam_enabled" {
  description = "Status of Windows IPAM enablement job"
  value       = kubernetes_job_v1.windows_k8s_config.metadata[0].name
}

output "ad_user_job_status" {
  description = "Status of AD user creation job (for vault_ldap_secrets dependency)"
  value       = kubernetes_job_v1.create_ad_user.metadata[0].name
}

output "vault_demo_initial_password" {
  description = "Initial password for vault-demo user (will be rotated by Vault)"
  value       = local.vault_demo_initial_password
  sensitive   = true
}
