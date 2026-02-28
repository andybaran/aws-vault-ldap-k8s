# Kubernetes authentication backend for Vault Secrets Operator
# Reference: https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/auth_backend

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
}

# Kubernetes auth backend configuration
# Reference: https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/kubernetes_auth_backend_config
resource "vault_kubernetes_auth_backend_config" "config" {
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = var.kubernetes_host
  kubernetes_ca_cert = base64decode(var.kubernetes_ca_cert)

  # When disable_local_ca_jwt is false, Vault validates JWT tokens locally using the CA cert
  # This is more reliable than calling the K8s API for token review
  disable_local_ca_jwt = false
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

# Kubernetes auth backend role for the LDAP app to poll Vault directly
resource "vault_kubernetes_auth_backend_role" "ldap_app" {
  count = var.ldap_dual_account ? 1 : 0

  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "ldap-app-role"
  bound_service_account_names      = ["ldap-app-vault-auth"]
  bound_service_account_namespaces = [var.kube_namespace]
  token_ttl                        = 600
  token_policies                   = [vault_policy.ldap_static_read.name]
  audience                         = "vault"
}

# Kubernetes auth backend role for Vault Agent sidecar deployment
resource "vault_kubernetes_auth_backend_role" "vault_agent_app" {
  count = var.ldap_dual_account ? 1 : 0

  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "vault-agent-app-role"
  bound_service_account_names      = ["ldap-app-vault-agent"]
  bound_service_account_namespaces = [var.kube_namespace]
  token_ttl                        = 600
  token_policies                   = [vault_policy.ldap_static_read.name]
  audience                         = "vault"
}

# Kubernetes auth backend role for CSI Driver deployment
resource "vault_kubernetes_auth_backend_role" "csi_app" {
  count = var.ldap_dual_account ? 1 : 0

  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "csi-app-role"
  bound_service_account_names      = ["ldap-app-csi"]
  bound_service_account_namespaces = [var.kube_namespace]
  token_ttl                        = 600
  token_policies                   = [vault_policy.ldap_static_read.name]
  audience                         = "vault"
}
