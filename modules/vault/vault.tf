resource "kubernetes_secret_v1" "vault_license" {
data = {
    license = base64encode(var.vault_license_key)
}
  metadata {
    name      = "vault-license"
    namespace = var.kube_namespace
}
}


resource "helm_release" "vault_cluster" {

  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  namespace  = var.kube_namespace
  version    = "0.31.0"
#   values = [<<-EOT
# global:
# server:
#   ha:
#     enabled: true
#   raft:
#     enabled: true
#   image:
#     repository: hashicorp/vault-enterprise
#     tag: 1.21.2-ent 
#   enterpriseLicense:
#     secretName: "vault-license"
# ui:
#   enabled: true
# EOT
# ]
    set = [
    {
        name  = "server.ha.enabled"
        value = "true"
    },
    {
        name  = "server.raft.enabled"
        value = "true"
    },
    {
        name = "server.image.repository"
        value = "hashicorp/vault-enterprise"
    },
    {
        name = "server.image.tag"
        value = "1.21.2-ent"
    },
    {
        name  = "server.enterpriseLicense.secretName"
        value = "vault-license"
    },
    {
        name  = "ui.enabled"
        value = "true"
    },

    ]
}
