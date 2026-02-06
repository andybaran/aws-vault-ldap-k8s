# Kubernetes Job to create the vault-demo user in Active Directory
# This job runs once after DC provisioning to create the user that Vault will manage

locals {
  ldap_server = var.ldap_dc_private_ip
  ldap_admin_dn = "CN=Administrator,CN=Users,DC=mydomain,DC=local"
  vault_demo_username = "vault-demo"
  vault_demo_initial_password = "VaultDemo123!" # Will be rotated by Vault immediately
}

# Secret containing LDAP admin credentials for user creation
resource "kubernetes_secret_v1" "ldap_admin_creds" {
  metadata {
    name      = "ldap-admin-creds"
    namespace = kubernetes_namespace_v1.simple_app.metadata[0].name
  }

  data = {
    admin_dn       = local.ldap_admin_dn
    admin_password = var.ldap_admin_password
  }

  type = "Opaque"
}

# ConfigMap with LDIF template for creating the vault-demo user
resource "kubernetes_config_map_v1" "create_ad_user_ldif" {
  metadata {
    name      = "create-ad-user-ldif"
    namespace = kubernetes_namespace_v1.simple_app.metadata[0].name
  }

  data = {
    "create-user.ldif" = <<-EOT
      dn: CN=${local.vault_demo_username},CN=Users,DC=mydomain,DC=local
      objectClass: top
      objectClass: person
      objectClass: organizationalPerson
      objectClass: user
      cn: ${local.vault_demo_username}
      sAMAccountName: ${local.vault_demo_username}
      userPrincipalName: ${local.vault_demo_username}@mydomain.local
      displayName: Vault Demo Service Account
      description: Service account managed by HashiCorp Vault for password rotation demo
      userAccountControl: 512
    EOT

    "set-password.sh" = <<-EOT
      #!/bin/bash
      set -e
      
      echo "Connecting to LDAP server at ${local.ldap_server}..."
      
      # Try to create the user
      echo "Creating user ${local.vault_demo_username}..."
      ldapadd -x -H ldap://${local.ldap_server} \
        -D "$ADMIN_DN" \
        -w "$ADMIN_PASSWORD" \
        -f /ldif/create-user.ldif || echo "User may already exist, continuing..."
      
      # Set the password using ldapmodify
      echo "Setting initial password..."
      ldappasswd -x -H ldap://${local.ldap_server} \
        -D "$ADMIN_DN" \
        -w "$ADMIN_PASSWORD" \
        -s "${local.vault_demo_initial_password}" \
        "CN=${local.vault_demo_username},CN=Users,DC=mydomain,DC=local"
      
      # Enable the account
      echo "Enabling the account..."
      cat <<EOF | ldapmodify -x -H ldap://${local.ldap_server} -D "$ADMIN_DN" -w "$ADMIN_PASSWORD"
      dn: CN=${local.vault_demo_username},CN=Users,DC=mydomain,DC=local
      changetype: modify
      replace: userAccountControl
      userAccountControl: 512
      EOF
      
      echo "User ${local.vault_demo_username} created successfully!"
      echo "Initial password: ${local.vault_demo_initial_password}"
      echo "Note: This password will be rotated by Vault on first use."
    EOT
  }
}

# Job to create the AD user
resource "kubernetes_job_v1" "create_ad_user" {
  metadata {
    name      = "create-ad-user"
    namespace = kubernetes_namespace_v1.simple_app.metadata[0].name
  }

  # Wait for the job to complete before Terraform marks it as created
  # This ensures vault_ldap_secrets component waits for the user to exist
  wait_for_completion = true
  
  # Timeout for job completion (default would be too short)
  timeouts {
    create = "5m"
    update = "5m"
  }

  spec {
    # Keep completed job for 1 hour for debugging
    ttl_seconds_after_finished = 3600
    
    template {
      metadata {
        labels = {
          app = "create-ad-user"
        }
      }

      spec {
        restart_policy = "OnFailure"

        container {
          name  = "create-ad-user"
          image = "ubuntu:22.04"
          
          command = ["/bin/bash", "-c"]
          args = [
            <<-EOT
              apt-get update && apt-get install -y ldap-utils
              chmod +x /scripts/set-password.sh
              /scripts/set-password.sh
            EOT
          ]

          env {
            name = "ADMIN_DN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.ldap_admin_creds.metadata[0].name
                key  = "admin_dn"
              }
            }
          }

          env {
            name = "ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.ldap_admin_creds.metadata[0].name
                key  = "admin_password"
              }
            }
          }

          volume_mount {
            name       = "ldif"
            mount_path = "/ldif"
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
          }
        }

        volume {
          name = "ldif"
          config_map {
            name = kubernetes_config_map_v1.create_ad_user_ldif.metadata[0].name
            items {
              key  = "create-user.ldif"
              path = "create-user.ldif"
            }
          }
        }

        volume {
          name = "scripts"
          config_map {
            name = kubernetes_config_map_v1.create_ad_user_ldif.metadata[0].name
            default_mode = "0755"
            items {
              key  = "set-password.sh"
              path = "set-password.sh"
            }
          }
        }
      }
    }
  }

  wait_for_completion = false
}

# Output the initial password (will be rotated by Vault)
output "vault_demo_initial_password" {
  description = "Initial password for vault-demo user (will be rotated by Vault)"
  value       = local.vault_demo_initial_password
  sensitive   = true
}
