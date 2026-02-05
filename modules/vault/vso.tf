# Vault Secrets Operator (VSO) Installation
# Reference: https://developer.hashicorp.com/vault/docs/platform/k8s/vso

resource "helm_release" "vault_secrets_operator" {
  name       = "vault-secrets-operator"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault-secrets-operator"
  namespace  = var.kube_namespace
  version    = "0.9.0"

  # VSO needs to be installed after Vault is ready
  depends_on = [
    helm_release.vault_cluster,
    kubernetes_job_v1.vault_init
  ]

  set = [
    {
      name  = "controller.manager.image.tag"
      value = "0.9.0"
    },
    {
      name  = "defaultVaultConnection.enabled"
      value = "false" # We'll create VaultConnection manually for more control
    },
    {
      name  = "defaultAuthMethod.enabled"
      value = "false" # We'll create VaultAuth manually for more control
    }
  ]
}

# VaultConnection - connects VSO to Vault
resource "kubernetes_manifest" "vault_connection" {
  depends_on = [
    helm_release.vault_secrets_operator,
    data.kubernetes_service_v1.vault
  ]

  manifest = {
    apiVersion = "secrets.hashicorp.com/v1beta1"
    kind       = "VaultConnection"
    metadata = {
      name      = "default"
      namespace = var.kube_namespace
    }
    spec = {
      address       = "http://${try(data.kubernetes_service_v1.vault.status[0].load_balancer[0].ingress[0].hostname, "vault.${var.kube_namespace}.svc.cluster.local")}:8200"
      skipTLSVerify = true
    }
  }

  # Skip validation since CRD may not be installed during plan
  computed_fields = ["spec"]
}

# VaultAuth - configures Kubernetes auth for VSO
resource "kubernetes_manifest" "vault_auth" {
  depends_on = [
    kubernetes_manifest.vault_connection,
    helm_release.vault_secrets_operator
  ]

  manifest = {
    apiVersion = "secrets.hashicorp.com/v1beta1"
    kind       = "VaultAuth"
    metadata = {
      name      = "default"
      namespace = var.kube_namespace
    }
    spec = {
      vaultConnectionRef = "default"  # References VaultConnection name
      method             = "kubernetes"
      mount              = "kubernetes"
      kubernetes = {
        role           = "vso-role"
        serviceAccount = kubernetes_service_account_v1.vso.metadata[0].name
        audiences      = ["vault"]
      }
    }
  }

  # Skip validation since CRD may not be installed during plan
  computed_fields = ["spec"]
}

# Service account for VSO to authenticate to Vault
resource "kubernetes_service_account_v1" "vso" {
  metadata {
    name      = "vso-auth"
    namespace = var.kube_namespace
  }
  automount_service_account_token = true
}

# ClusterRoleBinding for VSO service account
resource "kubernetes_cluster_role_binding_v1" "vso" {
  metadata {
    name = "vso-tokenreview-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.vso.metadata[0].name
    namespace = var.kube_namespace
  }
}
