resource "vault_auth_backend" "kube_auth" {
  #count      = var.step_2 ? 1 : 0
  #depends_on = [time_sleep.step_2]
  namespace  = vault_namespace.namespace.path
  type       = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "kube_auth_cfg" {
  #count              = var.step_2 ? 1 : 0
  #depends_on         = [time_sleep.step_2]
  namespace          = vault_namespace.namespace.path
  backend            = vault_auth_backend.kube_auth[0].path
  kubernetes_ca_cert = base64decode(module.eks.cluster_certificate_authority_data)
  kubernetes_host    = module.eks.cluster_endpoint
  token_reviewer_jwt = kubernetes_secret_v1.vault_token[0].data["token"]
}

resource "vault_kubernetes_auth_backend_role" "simple_app_role" {
  #count                            = var.step_2 ? 1 : 0
  #depends_on                       = [time_sleep.step_2]
  namespace                        = vault_namespace.namespace.path
  backend                          = vault_auth_backend.kube_auth[0].path
  role_name                        = "simple-app"
  bound_service_account_names      = [kubernetes_service_account_v1.vault[0].metadata.0.name]
  bound_service_account_namespaces = [kubernetes_namespace_v1.simple_app[0].metadata.0.name]
  token_max_ttl                    = 86400
  token_policies                   = [vault_policy.apps_policy[0].name]
  audience                         = "vault"
}
