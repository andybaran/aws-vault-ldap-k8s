output "kube_namespace" {
    description = "The Kubernetes namespace created for the application."
    value = kubernetes_namespace_v1.simple_app.metadata.0.name
    ephemeral = false
    sensitive = false
}