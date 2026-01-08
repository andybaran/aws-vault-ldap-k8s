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
  chart      = "hashicorp/vault"
  namespace  = var.kube_namespace
  version    = "0.31.0"
  values = [<<-EOT
global:
server:
    ha:
        enabled: true
    raft:
        enabled: true
    image:
        repository: hashicorp/vault-enterprise
        tag: 1.21.2-ent 
    enterpriseLicense:
        secretName: "vault-license"
ui:
    enabled: true
EOT
]
}
