# LDAP Credentials Application with Vault Secrets Operator
# This deployment demonstrates LDAP static role credentials delivered via VSO

locals {
  ldap_app_name        = "ldap-credentials-app"
  ldap_app_secret_name = "ldap-credentials"
  ldap_app_image       = "ghcr.io/andybaran/vault-ldap-demo:latest"
}

# VaultDynamicSecret CR for LDAP credentials
# Reference: https://developer.hashicorp.com/vault/docs/platform/k8s/vso/api-reference#vaultdynamicsecret
resource "kubernetes_manifest" "vault_ldap_secret" {
  manifest = {
    apiVersion = "secrets.hashicorp.com/v1beta1"
    kind       = "VaultDynamicSecret"
    metadata = {
      name      = local.ldap_app_name
      namespace = var.kube_namespace
    }
    spec = {
      mount = var.ldap_mount_path
      path  = "static-cred/${var.ldap_static_role_name}"
      destination = {
        name   = local.ldap_app_secret_name
        create = true
      }
      # allowStaticCreds enables syncing of periodically rotated credentials
      # (LDAP static roles) that have no lease TTL in the Vault response
      allowStaticCreds = true
      # refreshAfter tells VSO how often to re-sync the secret since
      # static credentials don't include a lease duration
      refreshAfter   = "8s"
      renewalPercent = 67
      vaultAuthRef   = var.vso_vault_auth_name
      rolloutRestartTargets = [
        {
          kind = "Deployment"
          name = local.ldap_app_name
        }
      ]
    }
  }

  # Bypass object validation since CRD may not be installed during plan
  computed_fields = ["spec"]
}

# Deployment for LDAP credentials display application
resource "kubernetes_deployment_v1" "ldap_app" {
  depends_on = [
    kubernetes_manifest.vault_ldap_secret,
  ]

  metadata {
    name      = local.ldap_app_name
    namespace = var.kube_namespace
    labels = {
      app = local.ldap_app_name
    }
  }

  spec {
    replicas = 2

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_unavailable = 1
        max_surge       = 1
      }
    }

    selector {
      match_labels = {
        app = local.ldap_app_name
      }
    }

    template {
      metadata {
        labels = {
          app = local.ldap_app_name
        }
      }

      spec {
        container {
          name              = local.ldap_app_name
          image             = local.ldap_app_image
          image_pull_policy = "Always"

          port {
            container_port = 8080
            name           = "http"
          }

          # Resource limits for demo purposes
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

          # Liveness probe
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

          # Readiness probe
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

          # Environment variables from LDAP secret
          # VSO syncs these from Vault LDAP static role
          env {
            name = "LDAP_USERNAME"
            value_from {
              secret_key_ref {
                name = local.ldap_app_secret_name
                key  = "username"
              }
            }
          }

          env {
            name = "LDAP_PASSWORD"
            value_from {
              secret_key_ref {
                name = local.ldap_app_secret_name
                key  = "password"
              }
            }
          }

          env {
            name = "LDAP_LAST_VAULT_PASSWORD"
            value_from {
              secret_key_ref {
                name = local.ldap_app_secret_name
                key  = "last_vault_rotation"
              }
            }
          }

          env {
            name = "ROTATION_PERIOD"
            value_from {
              secret_key_ref {
                name = local.ldap_app_secret_name
                key  = "rotation_period"
              }
            }
          }

          env {
            name = "ROTATION_TTL"
            value_from {
              secret_key_ref {
                name = local.ldap_app_secret_name
                key  = "ttl"
              }
            }
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
    # Prevent unnecessary replacement - only replace if critical changes
    create_before_destroy = true
  }
}

# Service for LDAP credentials application
resource "kubernetes_service_v1" "ldap_app" {
  metadata {
    name      = local.ldap_app_name
    namespace = var.kube_namespace
    labels = {
      app = local.ldap_app_name
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
      app = local.ldap_app_name
    }
  }
}

# Output the service information
output "ldap_app_service_name" {
  description = "Name of the LDAP credentials app service"
  value       = kubernetes_service_v1.ldap_app.metadata[0].name
}

output "ldap_app_service_type" {
  description = "Type of the LDAP credentials app service"
  value       = kubernetes_service_v1.ldap_app.spec[0].type
}

output "ldap_app_url" {
  description = "URL of the LDAP credentials app"
  value       = "http://${try(kubernetes_service_v1.ldap_app.status[0].load_balancer[0].ingress[0].hostname, "pending")}"
}
