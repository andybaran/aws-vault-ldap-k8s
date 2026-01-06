output "kube_namespace" {
    description = "The Kubernetes namespace created for the application."
    value = kubernetes_namespace_v1.simple_app.metadata.0.name
    ephemeral = false
    sensitive = false
}

output "vault_mount_credentials_path" {
    description = "The Vault mount path for the credentials KV store."
    value = vault_mount.credentials.path
}