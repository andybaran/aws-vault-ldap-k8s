resource "kubernetes_secret_v1" "vault_license" {
  data = {
    license = var.vault_license_key
  }
  metadata {
    name      = "vault-license"
    namespace = "default"
  }
  type = "Opaque"

}

resource "aws_eip" "nginx_ingress" {
  count = 3
}

resource "time_sleep" "eip_wait" {
  depends_on = [
    aws_eip.nginx_ingress
  ]
  destroy_duration = "60s"
}

resource "helm_release" "nginx_ingress" {
  depends_on = [
    time_sleep.eip_wait
  ]
  name            = "ingress-nginx"
  repository      = "https://kubernetes.github.io/ingress-nginx"
  chart           = "ingress-nginx"
  upgrade_install = true
  values = [<<-EOT
controller:
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
      service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: true
      service.beta.kubernetes.io/aws-load-balancer-eip-allocations: ${aws_eip.nginx_ingress[0].id},${aws_eip.nginx_ingress[1].id},${aws_eip.nginx_ingress[2].id}
      service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
    type: LoadBalancer
defaultBackend:
  enabled: true
EOT
  ]
}

resource "kubernetes_service_account_v1" "vault" {
  metadata {
    name      = "vault-auth"
    namespace = "default"
  }
  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "vault_token" {
  metadata {
    name      = kubernetes_service_account_v1.vault.metadata.0.name
    namespace = "default"
    annotations = {
      "kubernetes.io/service-account.name" = "vault-auth"
    }
  }
  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

resource "kubernetes_cluster_role_binding_v1" "vault" {
  metadata {
    name = "role-tokenreview-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.vault.metadata.0.name
    namespace = "default"
  }
}
