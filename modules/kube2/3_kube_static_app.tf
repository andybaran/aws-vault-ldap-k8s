locals {
  static_app_secret_name = "kv-secrets"
}

resource "kubernetes_manifest" "vault_static_secret" {
  manifest = yamldecode(<<-EOF
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: vault-static-secret
  namespace: ${var.kube_namespace}
spec:
  type: kv-v2
  mount: ${var.vault_mount_credentials_path}
  path: app/config
  destination:
    name: ${local.static_app_secret_name}
    create: true
  refreshAfter: 2s
  vaultAuthRef: default
  rolloutRestartTargets:
    - kind: Deployment
      name: "static-secrets"
EOF
  )
}

resource "kubernetes_deployment_v1" "static_app" {
  depends_on = [
    kubernetes_manifest.vault_static_secret,
  ]
  metadata {
    name      = "static-secrets"
    namespace = var.kube_namespace
  }

  spec {
    replicas = 3

    strategy {
      rolling_update {
        max_unavailable = 1
      }
    }

    selector {
      match_labels = {
        app = "static-secrets"
      }
    }

    template {
      metadata {
        labels = {
          app = "static-secrets"
        }
      }

      spec {
        container {
          name  = "static-secrets"
          image = "drum0r/demo-go-web:v1.1.0"
          port {
            container_port = 8080
          }

          resources {
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }

          liveness_probe {
            http_get {
              path   = "/health"
              scheme = "HTTP"
              port   = 8080
            }
          }

          env {
            name  = "TITLE"
            value = "Vault Secrets Operator is amazing!"
          }

          env {
            name  = "SUB_TITLE"
            value = "You can now manage your static secrets in Kubernetes using Vault."
          }

          env {
            name  = "LEARN_LINK"
            value = "https://developer.hashicorp.com/vault/docs/platform/k8s/vso"
          }

          env {
            name = "FIRST_MESSAGE"
            value_from {
              secret_key_ref {
                name = local.static_app_secret_name
                key  = "message"
              }
            }
          }

          env {
            name = "IMAGE_URL"
            value_from {
              secret_key_ref {
                name = local.static_app_secret_name
                key  = "image_url"
              }
            }
          }
        }
      }
    }
  }
  lifecycle {
    ignore_changes = [spec[0].template[0].metadata[0].annotations]
  }
}

resource "kubernetes_service_v1" "static_app" {
  # count      = var.step_3 ? 1 : 0
  # depends_on = [time_sleep.step_3]
  metadata {
    name      = kubernetes_deployment_v1.static_app.metadata.0.name
    namespace = var.kube_namespace
  }

  spec {
    type = "ClusterIP"

    port {
      port        = 8080
      target_port = 8080
    }

    selector = {
      app = "static-secrets"
    }
  }
}

