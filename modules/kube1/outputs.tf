output "kube_namespace" {
  description = "The Kubernetes namespace created for the application."
  value       = kubernetes_namespace_v1.simple_app.metadata.0.name
  ephemeral   = false
  sensitive   = false
}

output "ad_user_job_status" {
  description = "Status of the AD user creation job - used to ensure job completes before Vault LDAP secrets engine configuration"
  value       = kubernetes_job_v1.create_ad_user.metadata[0].name
  ephemeral   = false
  sensitive   = false
}
