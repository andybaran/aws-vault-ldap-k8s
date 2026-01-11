# resource "helm_release" "vault_secrets_operator" {
#   name       = "vault-secrets-operator"
#   repository = "https://helm.releases.hashicorp.com"
#   chart      = "vault-secrets-operator"
#   namespace  = kubernetes_namespace_v1.simple_app.metadata.0.name
#   version    = "0.8.1"
#   values = [<<-EOT
#   defaultVaultConnection:
#     enabled: true
#     address: ${var.vault_public_endpoint}
#   defaultAuthMethod:
#     enabled: true
#     namespace: ${vault_namespace.namespace.id}
#     allowedNamespaces:
#       - ${try(kubernetes_namespace_v1.simple_app.metadata.0.name, null)}
#     method: ${try(vault_auth_backend.kube_auth.type, null)}
#     mount: ${try(vault_auth_backend.kube_auth.path, null)}
#     kubernetes:
#       role: ${try(vault_kubernetes_auth_backend_role.simple_app_role.role_name, null)}
#       serviceAccount: ${try(kubernetes_service_account_v1.vault.metadata.0.name, null)}
#       tokenAudiences:
#         - vault
# EOT
#   ]
# }
