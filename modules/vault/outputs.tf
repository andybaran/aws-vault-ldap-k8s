data "kubernetes_secret_v1" "vault_init_data" {
  metadata {
    name      = "vault-init-data"
    namespace = var.kube_namespace
  }
  depends_on = [kubernetes_job_v1.vault_init]
}

locals {
  vault_init_json = try(jsondecode(data.kubernetes_secret_v1.vault_init_data.data["init.json"]), null)
  unseal_keys_b64 = try(local.vault_init_json.unseal_keys_b64, [])
  root_token      = try(local.vault_init_json.root_token, "")
}

output "vault_unseal_keys" {
  description = "Vault unseal keys (base64 encoded)"
  value       = local.unseal_keys_b64
  sensitive   = true
}

output "vault_root_token" {
  description = "Vault root token"
  value       = local.root_token
  sensitive   = false
}

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
