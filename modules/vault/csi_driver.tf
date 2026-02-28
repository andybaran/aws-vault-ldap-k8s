# Secrets Store CSI Driver
# The Vault Helm chart has csi.enabled=true (Vault CSI Provider),
# but the Secrets Store CSI Driver itself needs separate installation.
# Reference: https://secrets-store-csi-driver.sigs.k8s.io/

resource "helm_release" "secrets_store_csi_driver" {
  count = var.ldap_dual_account ? 1 : 0

  name       = "secrets-store-csi-driver"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  namespace  = var.kube_namespace
  version    = "1.4.7"

  set = [
    {
      name  = "syncSecret.enabled"
      value = "true"
    },
    {
      name  = "enableSecretRotation"
      value = "true"
    },
    {
      name  = "rotationPollInterval"
      value = "30s"
    }
  ]

  depends_on = [helm_release.vault_cluster]
}
