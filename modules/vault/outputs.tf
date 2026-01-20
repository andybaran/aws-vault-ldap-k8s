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

data "kubernetes_service_v1" "vault" {
  metadata {
    name      = "vault"
    namespace = var.kube_namespace
  }
  depends_on = [helm_release.vault_cluster]
}

data "kubernetes_service_v1" "vault_ui" {
  metadata {
    name      = "vault-ui"
    namespace = var.kube_namespace
  }
  depends_on = [helm_release.vault_cluster]
}

output "vault_loadbalancer_hostname" {
  description = "Internal LoadBalancer hostname for Vault API"
  value       = "http://${try(data.kubernetes_service_v1.vault.status[0].load_balancer[0].ingress[0].hostname, "pending")}:8200"
}

output "vault_ui_loadbalancer_hostname" {
  description = "Internal LoadBalancer hostname for Vault UI"
  value       = "http://${try(data.kubernetes_service_v1.vault_ui.status[0].load_balancer[0].ingress[0].hostname, "pending")}:8200"
}
