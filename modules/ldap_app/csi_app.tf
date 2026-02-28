# CSI Driver Deployment for LDAP Credentials
# This deployment demonstrates LDAP static role credentials delivered via Secrets Store CSI Driver
# Uses service account svc-lib

locals {
  csi_app_name = "ldap-app-csi"
}

# Service account for CSI Driver authentication
resource "kubernetes_service_account_v1" "ldap_app_csi" {
  count = var.ldap_dual_account ? 1 : 0

  metadata {
    name      = "ldap-app-csi"
    namespace = var.kube_namespace
  }
  automount_service_account_token = true
}

# SecretProviderClass for LDAP credentials via Vault CSI provider
resource "kubernetes_manifest" "ldap_csi_secret_provider" {
  count = var.ldap_dual_account ? 1 : 0

  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = "ldap-csi-credentials"
      namespace = var.kube_namespace
    }
    spec = {
      provider = "vault"
      parameters = {
        roleName     = "csi-app-role"
        vaultAddress = "http://vault.${var.kube_namespace}.svc.cluster.local:8200"
        objects = yamlencode([
          {
            objectName = "username"
            secretPath = "ldap/static-cred/svc-lib"
            secretKey  = "username"
          },
          {
            objectName = "password"
            secretPath = "ldap/static-cred/svc-lib"
            secretKey  = "password"
          },
          {
            objectName = "last_vault_rotation"
            secretPath = "ldap/static-cred/svc-lib"
            secretKey  = "last_vault_rotation"
          },
          {
            objectName = "rotation_period"
            secretPath = "ldap/static-cred/svc-lib"
            secretKey  = "rotation_period"
          },
          {
            objectName = "ttl"
            secretPath = "ldap/static-cred/svc-lib"
            secretKey  = "ttl"
          }
        ])
      }
    }
  }

  computed_fields = ["spec"]
}

# Deployment for CSI Driver LDAP credentials application
resource "kubernetes_deployment_v1" "ldap_app_csi" {
  count = var.ldap_dual_account ? 1 : 0

  metadata {
    name      = local.csi_app_name
    namespace = var.kube_namespace
    labels = {
      app = local.csi_app_name
    }
  }

  spec {
    replicas = 1

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_unavailable = 1
        max_surge       = 1
      }
    }

    selector {
      match_labels = {
        app = local.csi_app_name
      }
    }

    template {
      metadata {
        labels = {
          app = local.csi_app_name
        }
      }

      spec {
        service_account_name            = kubernetes_service_account_v1.ldap_app_csi[0].metadata[0].name
        automount_service_account_token = true

        # CSI volume for secrets from Vault
        volume {
          name = "vault-secrets"
          csi {
            driver    = "secrets-store.csi.k8s.io"
            read_only = true
            volume_attributes = {
              secretProviderClass = "ldap-csi-credentials"
            }
          }
        }

        container {
          name              = "ldap-app"
          image             = var.ldap_app_image
          image_pull_policy = "Always"

          port {
            container_port = 8080
            name           = "http"
          }

          volume_mount {
            name       = "vault-secrets"
            mount_path = "/vault/secrets"
            read_only  = true
          }

          resources {
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }

          liveness_probe {
            http_get {
              path   = "/health"
              port   = 8080
              scheme = "HTTP"
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path   = "/health"
              port   = 8080
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          env {
            name  = "SECRET_DELIVERY_METHOD"
            value = "vault-csi-driver"
          }

          env {
            name  = "SECRETS_FILE_PATH"
            value = "/vault/secrets"
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      spec[0].template[0].metadata[0].annotations,
      metadata[0].annotations
    ]
    create_before_destroy = true
  }

  depends_on = [kubernetes_manifest.ldap_csi_secret_provider]
}

# Service for CSI Driver LDAP credentials application
resource "kubernetes_service_v1" "ldap_app_csi" {
  count = var.ldap_dual_account ? 1 : 0

  metadata {
    name      = local.csi_app_name
    namespace = var.kube_namespace
    labels = {
      app = local.csi_app_name
    }
  }

  spec {
    type = "LoadBalancer"

    port {
      name        = "http"
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }

    selector = {
      app = local.csi_app_name
    }
  }
}

# Output the service information
output "ldap_app_csi_url" {
  description = "URL of the CSI Driver LDAP app"
  value       = var.ldap_dual_account ? "http://${try(kubernetes_service_v1.ldap_app_csi[0].status[0].load_balancer[0].ingress[0].hostname, "pending")}" : ""
}
