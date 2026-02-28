# Vault Agent Sidecar Deployment for LDAP Credentials
# This deployment demonstrates LDAP static role credentials delivered via Vault Agent sidecar
# Uses service account svc-single

locals {
  vault_agent_app_name = "ldap-app-vault-agent"
}

# Service account for Vault Agent authentication
resource "kubernetes_service_account_v1" "ldap_app_vault_agent" {
  count = var.ldap_dual_account ? 1 : 0

  metadata {
    name      = "ldap-app-vault-agent"
    namespace = var.kube_namespace
  }
  automount_service_account_token = true
}

# ConfigMap containing Vault Agent configuration
resource "kubernetes_config_map_v1" "vault_agent_config" {
  count = var.ldap_dual_account ? 1 : 0

  metadata {
    name      = "vault-agent-config"
    namespace = var.kube_namespace
  }

  data = {
    "vault-agent-config.hcl" = <<-EOT
      exit_after_auth = false
      pid_file = "/home/vault/pidfile"

      vault {
        address = "http://vault.${var.kube_namespace}.svc.cluster.local:8200"
      }

      auto_auth {
        method "kubernetes" {
          mount_path = "auth/kubernetes"
          config = {
            role       = "vault-agent-app-role"
            token_path = "/var/run/secrets/vault/token"
          }
        }
        sink "file" {
          config = {
            path = "/home/vault/.vault-token"
          }
        }
      }

      template_config {
        static_secret_render_interval = "30s"
      }

      template {
        contents = <<TMPL
      LDAP_USERNAME={{ with secret "ldap/static-cred/svc-single" }}{{ .Data.username }}{{ end }}
      LDAP_PASSWORD={{ with secret "ldap/static-cred/svc-single" }}{{ .Data.password }}{{ end }}
      LDAP_LAST_VAULT_PASSWORD={{ with secret "ldap/static-cred/svc-single" }}{{ .Data.last_vault_rotation }}{{ end }}
      ROTATION_PERIOD={{ with secret "ldap/static-cred/svc-single" }}{{ .Data.rotation_period }}{{ end }}
      ROTATION_TTL={{ with secret "ldap/static-cred/svc-single" }}{{ .Data.ttl }}{{ end }}
      TMPL
        destination = "/vault/secrets/ldap-creds"
      }
    EOT

    "vault-agent-init-config.hcl" = <<-EOT
      exit_after_auth = true
      pid_file = "/home/vault/pidfile"

      vault {
        address = "http://vault.${var.kube_namespace}.svc.cluster.local:8200"
      }

      auto_auth {
        method "kubernetes" {
          mount_path = "auth/kubernetes"
          config = {
            role       = "vault-agent-app-role"
            token_path = "/var/run/secrets/vault/token"
          }
        }
        sink "file" {
          config = {
            path = "/home/vault/.vault-token"
          }
        }
      }

      template {
        contents = <<TMPL
      LDAP_USERNAME={{ with secret "ldap/static-cred/svc-single" }}{{ .Data.username }}{{ end }}
      LDAP_PASSWORD={{ with secret "ldap/static-cred/svc-single" }}{{ .Data.password }}{{ end }}
      LDAP_LAST_VAULT_PASSWORD={{ with secret "ldap/static-cred/svc-single" }}{{ .Data.last_vault_rotation }}{{ end }}
      ROTATION_PERIOD={{ with secret "ldap/static-cred/svc-single" }}{{ .Data.rotation_period }}{{ end }}
      ROTATION_TTL={{ with secret "ldap/static-cred/svc-single" }}{{ .Data.ttl }}{{ end }}
      TMPL
        destination = "/vault/secrets/ldap-creds"
      }
    EOT
  }
}

# Deployment for Vault Agent sidecar LDAP credentials application
resource "kubernetes_deployment_v1" "ldap_app_vault_agent" {
  count = var.ldap_dual_account ? 1 : 0

  metadata {
    name      = local.vault_agent_app_name
    namespace = var.kube_namespace
    labels = {
      app = local.vault_agent_app_name
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
        app = local.vault_agent_app_name
      }
    }

    template {
      metadata {
        labels = {
          app = local.vault_agent_app_name
        }
      }

      spec {
        service_account_name            = kubernetes_service_account_v1.ldap_app_vault_agent[0].metadata[0].name
        automount_service_account_token = true

        # Shared volume for secrets rendered by Vault Agent
        volume {
          name = "vault-secrets"
          empty_dir {}
        }

        # Vault Agent config volume
        volume {
          name = "vault-agent-config"
          config_map {
            name = kubernetes_config_map_v1.vault_agent_config[0].metadata[0].name
          }
        }

        # Projected SA token with 'vault' audience for Vault K8s auth
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

        # Init container: Vault Agent in init mode to pre-render credentials
        init_container {
          name  = "vault-agent-init"
          image = var.vault_agent_image

          args = ["agent", "-config=/vault/config/vault-agent-init-config.hcl"]

          volume_mount {
            name       = "vault-secrets"
            mount_path = "/vault/secrets"
          }

          volume_mount {
            name       = "vault-agent-config"
            mount_path = "/vault/config"
            read_only  = true
          }

          volume_mount {
            name       = "vault-token"
            mount_path = "/var/run/secrets/vault"
            read_only  = true
          }

          resources {
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }
        }

        # Sidecar container: Vault Agent for ongoing refresh
        container {
          name  = "vault-agent"
          image = var.vault_agent_image

          args = ["agent", "-config=/vault/config/vault-agent-config.hcl"]

          volume_mount {
            name       = "vault-secrets"
            mount_path = "/vault/secrets"
          }

          volume_mount {
            name       = "vault-agent-config"
            mount_path = "/vault/config"
            read_only  = true
          }

          volume_mount {
            name       = "vault-token"
            mount_path = "/var/run/secrets/vault"
            read_only  = true
          }

          resources {
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }
        }

        # Application container
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
            value = "vault-agent-sidecar"
          }

          env {
            name  = "SECRETS_FILE_PATH"
            value = "/vault/secrets/ldap-creds"
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
}

# Service for Vault Agent sidecar LDAP credentials application
resource "kubernetes_service_v1" "ldap_app_vault_agent" {
  count = var.ldap_dual_account ? 1 : 0

  metadata {
    name      = local.vault_agent_app_name
    namespace = var.kube_namespace
    labels = {
      app = local.vault_agent_app_name
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
      app = local.vault_agent_app_name
    }
  }
}

# Output the service information
output "ldap_app_vault_agent_url" {
  description = "URL of the Vault Agent sidecar LDAP app"
  value       = var.ldap_dual_account ? "http://${try(kubernetes_service_v1.ldap_app_vault_agent[0].status[0].load_balancer[0].ingress[0].hostname, "pending")}" : ""
}
