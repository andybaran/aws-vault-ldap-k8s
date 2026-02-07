output "kube_namespace" {
  description = "The Kubernetes namespace for the application (default)."
  value       = "default"
  ephemeral   = false
  sensitive   = false
}
