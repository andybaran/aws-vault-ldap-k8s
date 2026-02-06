# Kubernetes authentication backend for Vault Secrets Operator
# Reference: https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/auth_backend

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
}

# Kubernetes auth backend configuration
# Reference: https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/kubernetes_auth_backend_config
resource "vault_kubernetes_auth_backend_config" "config" {
  backend         = vault_auth_backend.kubernetes.path
  kubernetes_host = var.kubernetes_host
  
  # Use the service account token for auth instead of CA cert
  # This is more reliable in EKS environments
  disable_local_ca_jwt = true
}

# Kubernetes auth backend role for VSO
# Reference: https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/kubernetes_auth_backend_role
resource "vault_kubernetes_auth_backend_role" "vso" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "vso-role"
  bound_service_account_names      = ["vso-auth"]
  bound_service_account_namespaces = [var.kube_namespace]
  token_ttl                        = 600
  token_policies                   = [vault_policy.ldap_static_read.name]
  audience                         = "vault"
}
