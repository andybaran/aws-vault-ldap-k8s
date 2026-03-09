# OpenLDAP on EKS — lightweight LDAP server for Vault demo
# Deploys the Bitnami OpenLDAP container with pre-configured service accounts
# matching the same naming conventions as the Active Directory module.

locals {
  # Convert domain like "demo.hashicorp" to base DN "dc=demo,dc=hashicorp"
  domain_parts = split(".", var.openldap_domain)
  base_dn      = join(",", [for part in local.domain_parts : "dc=${part}"])
  user_ou_dn   = "ou=users,${local.base_dn}"

  # Service accounts matching the AD module's naming
  service_accounts = ["svc-rotate-a", "svc-rotate-b", "svc-rotate-c", "svc-rotate-d", "svc-rotate-e", "svc-rotate-f", "svc-single", "svc-lib"]
}

# Generate random passwords for each service account (same pattern as AWS_DC module)
resource "random_password" "service_account_password" {
  for_each = var.enabled ? toset(local.service_accounts) : toset([])

  length           = 16
  override_special = "!@#"
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}

# ConfigMap with custom LDIF to bootstrap the organizational structure and service accounts
resource "kubernetes_config_map_v1" "openldap_bootstrap" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "${var.prefix}-openldap-bootstrap"
    namespace = var.kube_namespace
  }

  data = {
    "01-ou-structure.ldif" = <<-LDIF
      dn: ou=users,${local.base_dn}
      objectClass: organizationalUnit
      objectClass: top
      ou: users
      description: Service accounts for Vault LDAP demo

      dn: ou=groups,${local.base_dn}
      objectClass: organizationalUnit
      objectClass: top
      ou: groups
      description: Groups for Vault LDAP demo

      dn: cn=vault-managed,ou=groups,${local.base_dn}
      objectClass: groupOfNames
      objectClass: top
      cn: vault-managed
      description: Accounts managed by Vault for credential rotation
      ${join("\n      ", [for acct in local.service_accounts : "member: cn=${acct},ou=users,${local.base_dn}"])}
    LDIF

    "02-service-accounts.ldif" = join("\n\n", [
      for acct in local.service_accounts : <<-LDIF
      dn: cn=${acct},ou=users,${local.base_dn}
      objectClass: inetOrgPerson
      objectClass: top
      cn: ${acct}
      sn: ${acct}
      uid: ${acct}
      userPassword: ${random_password.service_account_password[acct].result}
      description: Vault-managed service account for LDAP rotation demo
    LDIF
    ])
  }
}

# Kubernetes Secret for OpenLDAP admin credentials
resource "kubernetes_secret_v1" "openldap_admin" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "${var.prefix}-openldap-admin"
    namespace = var.kube_namespace
  }

  data = {
    LDAP_ADMIN_PASSWORD    = var.openldap_admin_password
    LDAP_CONFIG_PASSWORD   = var.openldap_admin_password
  }
}

# OpenLDAP Deployment using the Bitnami container image
resource "kubernetes_deployment_v1" "openldap" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "${var.prefix}-openldap"
    namespace = var.kube_namespace
    labels = {
      app = "openldap"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "openldap"
      }
    }

    template {
      metadata {
        labels = {
          app = "openldap"
        }
      }

      spec {
        container {
          name  = "openldap"
          image = "bitnami/openldap:2.6"

          port {
            container_port = 1389
            name           = "ldap"
          }

          port {
            container_port = 1636
            name           = "ldaps"
          }

          env {
            name  = "LDAP_ROOT"
            value = local.base_dn
          }

          env {
            name  = "LDAP_ADMIN_USERNAME"
            value = "admin"
          }

          env {
            name = "LDAP_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.openldap_admin[0].metadata[0].name
                key  = "LDAP_ADMIN_PASSWORD"
              }
            }
          }

          env {
            name  = "LDAP_CONFIG_ADMIN_ENABLED"
            value = "yes"
          }

          env {
            name  = "LDAP_CONFIG_ADMIN_USERNAME"
            value = "admin"
          }

          env {
            name = "LDAP_CONFIG_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.openldap_admin[0].metadata[0].name
                key  = "LDAP_CONFIG_PASSWORD"
              }
            }
          }

          # Skip the default user tree — we use custom LDIF files instead
          env {
            name  = "LDAP_SKIP_DEFAULT_TREE"
            value = "yes"
          }

          env {
            name  = "LDAP_CUSTOM_LDIF_DIR"
            value = "/ldifs"
          }

          env {
            name  = "LDAP_EXTRA_SCHEMAS"
            value = "cosine,inetorgperson,nis"
          }

          # Allow anonymous binding (disabled — Vault always binds with admin)
          env {
            name  = "LDAP_ALLOW_ANON_BINDING"
            value = "no"
          }

          # Use cleartext password hashing so Vault can modify passwords via LDAP modify
          env {
            name  = "LDAP_PASSWORD_HASH"
            value = "{SSHA}"
          }

          volume_mount {
            name       = "ldif-bootstrap"
            mount_path = "/ldifs"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          readiness_probe {
            tcp_socket {
              port = 1389
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }

          liveness_probe {
            tcp_socket {
              port = 1389
            }
            initial_delay_seconds = 30
            period_seconds        = 15
          }
        }

        volume {
          name = "ldif-bootstrap"
          config_map {
            name = kubernetes_config_map_v1.openldap_bootstrap[0].metadata[0].name
          }
        }
      }
    }
  }
}

# ClusterIP Service for OpenLDAP — accessible within the cluster
resource "kubernetes_service_v1" "openldap" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "openldap"
    namespace = var.kube_namespace
    labels = {
      app = "openldap"
    }
  }

  spec {
    selector = {
      app = "openldap"
    }

    port {
      name        = "ldap"
      port        = 389
      target_port = 1389
      protocol    = "TCP"
    }

    port {
      name        = "ldaps"
      port        = 636
      target_port = 1636
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

# Wait for OpenLDAP to be ready before other components connect
resource "time_sleep" "wait_for_openldap" {
  count = var.enabled ? 1 : 0

  depends_on = [
    kubernetes_deployment_v1.openldap[0],
    kubernetes_service_v1.openldap[0]
  ]

  create_duration = "30s"
}
