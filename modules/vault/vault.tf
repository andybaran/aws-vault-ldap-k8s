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
            name = "global.tlsDisable"
            value = "true"
        },
    {
        name  = "server.ha.enabled"
        value = "true"
    },
    {
        name  = "server.ha.raft.enabled"
        value = "true"
    },
        {
        name  = "server.ha.raft.setNodeId"
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
        name  = "server.enterpriseLicense.secretKey"
        value = "license"
    },
    {
        name  = "ui.enabled"
        value = "true"
    },
    {
        name  = "server.dataStorage.enabled"
        value = "true"
    },
    {
        name  = "server.dataStorage.size"
        value = "10Gi"
    },
    {
        name  = "server.dataStorage.storageClass"
        value = kubernetes_storage_class_v1.vault_storage.metadata[0].name
    },
    {
        name  = "server.dataStorage.accessMode"
        value = "ReadWriteOnce"
    },
    {
        name  = "server.auditStorage.enabled"
        value = "true"
    },
    {
        name  = "server.auditStorage.size"
        value = "10Gi"
    },
    {
        name  = "server.auditStorage.storageClass"
        value = kubernetes_storage_class_v1.vault_storage.metadata[0].name
    },
    {
        name  = "server.auditStorage.accessMode"
        value = "ReadWriteOnce"
    },
    {
        name = "injector.enabled"
        value = "false"
    },
    {
        name = "ingress.enabled"
        value = "true"
    },
    {
        name = "csi.enabled"
        value = "true"
    },
    {
        name = "server.service.type"
        value = "LoadBalancer"
    },
    {
        name = "server.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
        value = "nlb"
    },
    {
        name = "server.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
        value = "internal"
    },
    {
        name = "server.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-backend-protocol"
        value = "tcp"
    },
    {
        name = "server.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-healthcheck-path"
        value = "/v1/sys/health?standbyok=false&perfstandbyok=false"
    },
    {
        name = "server.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-healthcheck-protocol"
        value = "http"
    },
    {
        name  = "server.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-healthcheck-port"
        value = "traffic-port"
    },
    {
        name = "ui.serviceType"
        value = "LoadBalancer"
    },
    {
        name = "ui.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
        value = "nlb"
    },
    {
        name = "ui.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
        value = "internal"
    }

    ]
}
