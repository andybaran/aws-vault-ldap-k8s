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

# SecretProviderClass for LDAP dual-account credentials via Vault CSI provider
# Uses full JSON response approach since CSI can't conditionally extract fields
# (standby_* fields only present during grace_period state)
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
        audience     = "vault"
        objects = yamlencode([
          {
            objectName = "username"
            secretPath = "ldap/static-cred/csi-dual-role"
            secretKey  = "username"
          },
          {
            objectName = "password"
            secretPath = "ldap/static-cred/csi-dual-role"
            secretKey  = "password"
          },
          {
            objectName = "rotation_state"
            secretPath = "ldap/static-cred/csi-dual-role"
            secretKey  = "rotation_state"
          },
          {
            objectName = "active_account"
            secretPath = "ldap/static-cred/csi-dual-role"
            secretKey  = "active_account"
          },
          {
            objectName = "ttl"
            secretPath = "ldap/static-cred/csi-dual-role"
            secretKey  = "ttl"
          },
          {
            objectName = "rotation_period"
            secretPath = "ldap/static-cred/csi-dual-role"
            secretKey  = "rotation_period"
          },
          {
            objectName = "last_vault_rotation"
            secretPath = "ldap/static-cred/csi-dual-role"
            secretKey  = "last_vault_rotation"
          },
          {
            objectName = "ldap-creds.json"
            secretPath = "ldap/static-cred/csi-dual-role"
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

        # Projected SA token with audience "vault" for direct Vault API polling
        volume {
          name = "vault-token"
          projected {
            sources {
              service_account_token {
                audience           = "vault"
                expiration_seconds = 7200
                path               = "token"
              }
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

          volume_mount {
            name       = "vault-token"
            mount_path = "/var/run/secrets/vault"
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

          env {
            name  = "DUAL_ACCOUNT_MODE"
            value = "true"
          }

          env {
            name  = "VAULT_ADDR"
            value = "http://vault.${var.kube_namespace}.svc.cluster.local:8200"
          }

          env {
            name  = "VAULT_AUTH_ROLE"
            value = "csi-app-role"
          }

          env {
            name  = "LDAP_MOUNT_PATH"
            value = var.ldap_mount_path
          }

          env {
            name  = "LDAP_STATIC_ROLE_NAME"
            value = "csi-dual-role"
          }

          env {
            name  = "GRACE_PERIOD"
            value = tostring(var.grace_period)
          }

          env {
            name  = "ROTATION_PERIOD"
            value = tostring(var.static_role_rotation_period)
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
