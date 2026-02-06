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
      userAccountControl: 514
    EOT

    "set-password.sh" = <<-EOT
      #!/bin/bash
      set -e
      
      LDAP_SERVER="${local.ldap_server}"
      VAULT_USER="${local.vault_demo_username}"
      INITIAL_PASSWORD="${local.vault_demo_initial_password}"
      USER_DN="CN=$VAULT_USER,CN=Users,DC=mydomain,DC=local"
      MAX_RETRIES=30
      RETRY_DELAY=10
      
      echo "==============================================="
      echo "AD User Creation Job Starting"
      echo "LDAP Server: $LDAP_SERVER"
      echo "User: $VAULT_USER"
      echo "User DN: $USER_DN"
      echo "==============================================="
      
      # Wait for LDAP server to be ready
      echo "Waiting for LDAP server to be ready..."
      for i in $(seq 1 $MAX_RETRIES); do
        if timeout 5 bash -c "echo > /dev/tcp/$LDAP_SERVER/389" 2>/dev/null; then
          echo "✓ LDAP server is reachable on port 389"
          break
        fi
        
        if [ $i -eq $MAX_RETRIES ]; then
          echo "✗ ERROR: LDAP server not reachable after $MAX_RETRIES attempts"
          echo "Network debugging:"
          echo "- Testing DNS resolution:"
          nslookup $LDAP_SERVER || echo "DNS resolution failed"
          echo "- Testing connectivity:"
          nc -zv $LDAP_SERVER 389 2>&1 || echo "TCP connection failed"
          exit 1
        fi
        
        echo "Waiting for LDAP server... (attempt $i/$MAX_RETRIES)"
        sleep $RETRY_DELAY
      done
      
      # Additional wait for LDAP service to be fully initialized
      echo "Waiting 10 seconds for LDAP service to fully initialize..."
      sleep 10
      
      # Test LDAP bind before attempting user creation
      echo "Testing LDAP authentication..."
      if ! ldapwhoami -x -H ldap://$LDAP_SERVER -D "$ADMIN_DN" -w "$ADMIN_PASSWORD"; then
        echo "✗ ERROR: LDAP authentication failed"
        echo "Admin DN: $ADMIN_DN"
        exit 1
      fi
      echo "✓ LDAP authentication successful"
      
      # Function to encode password for unicodePwd attribute
      # AD requires: "password" in UTF-16LE, base64 encoded
      encode_password() {
        local pwd="$1"
        # Add quotes around password and encode to UTF-16LE, then base64
        echo -n "\"$pwd\"" | iconv -f UTF-8 -t UTF-16LE | base64 -w 0
      }
      
      ENCODED_PASSWORD=$(encode_password "$INITIAL_PASSWORD")
      
      # Check if user already exists and delete if so (demo environment)
      echo "Checking if user $VAULT_USER already exists..."
      if ldapsearch -x -H ldap://$LDAP_SERVER \
          -D "$ADMIN_DN" \
          -w "$ADMIN_PASSWORD" \
          -b "$USER_DN" \
          "(objectClass=*)" dn 2>/dev/null | grep -q "^dn:"; then
        echo "✓ User $VAULT_USER already exists - deleting for fresh start (demo mode)"
        if ldapdelete -x -H ldap://$LDAP_SERVER \
            -D "$ADMIN_DN" \
            -w "$ADMIN_PASSWORD" \
            "$USER_DN"; then
          echo "✓ Existing user deleted successfully"
        else
          echo "⚠ Warning: Failed to delete existing user, will try to create anyway"
        fi
      else
        echo "✓ User $VAULT_USER does not exist, proceeding with creation"
      fi
      
      # Create user with password using unicodePwd (AD-specific method)
      echo "Creating user $VAULT_USER with password..."
      echo "Note: Using unicodePwd attribute (AD-specific, not standard LDAP)"
      
      # Create LDIF with unicodePwd
      cat > /tmp/create-user-with-password.ldif <<LDIF
      dn: $USER_DN
      objectClass: top
      objectClass: person
      objectClass: organizationalPerson
      objectClass: user
      cn: $VAULT_USER
      sAMAccountName: $VAULT_USER
      userPrincipalName: $VAULT_USER@mydomain.local
      displayName: Vault Demo Service Account
      description: Service account managed by HashiCorp Vault for password rotation demo
      unicodePwd:: $ENCODED_PASSWORD
      userAccountControl: 512
      LDIF
      
      if ldapadd -x -H ldap://$LDAP_SERVER \
          -D "$ADMIN_DN" \
          -w "$ADMIN_PASSWORD" \
          -f /tmp/create-user-with-password.ldif; then
        echo "✓ User created successfully with password"
      else
        echo "✗ Failed to create user with password"
        echo "Debugging: Showing LDIF content (password redacted):"
        sed 's/unicodePwd::.*/unicodePwd:: <REDACTED>/' /tmp/create-user-with-password.ldif
        exit 1
      fi
      
      # Verify user was created correctly
      echo "Verifying user creation..."
      if ldapsearch -x -H ldap://$LDAP_SERVER \
          -D "$ADMIN_DN" \
          -w "$ADMIN_PASSWORD" \
          -b "$USER_DN" \
          "(objectClass=*)" sAMAccountName userAccountControl | grep -q "sAMAccountName: $VAULT_USER"; then
        echo "✓ User verification successful"
      else
        echo "⚠ Warning: User verification failed, but continuing"
      fi
      
      # Test that the password works
      echo "Testing user authentication with new password..."
      if ldapwhoami -x -H ldap://$LDAP_SERVER \
          -D "$USER_DN" \
          -w "$INITIAL_PASSWORD"; then
        echo "✓ User authentication successful - password is working"
      else
        echo "⚠ Warning: User authentication test failed"
      fi
      
      echo "==============================================="
      echo "✓ AD User Creation Job Completed Successfully"
      echo "User: $VAULT_USER"
      echo "DN: $USER_DN"
      echo "Initial password: $INITIAL_PASSWORD"
      echo "Note: This password will be rotated by Vault"
      echo "==============================================="
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
  
  # Timeout for job completion (increased to accommodate retry logic)
  # Max retries: 30 * 10 seconds = 5 minutes + installation time
  timeouts {
    create = "10m"
    update = "10m"
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
              set -e
              echo "Installing dependencies..."
              apt-get update -qq
              apt-get install -y -qq ldap-utils netcat-openbsd dnsutils > /dev/null 2>&1
              
              echo "Copying script to writable location..."
              cp /scripts/set-password.sh /tmp/set-password.sh
              chmod +x /tmp/set-password.sh
              
              echo "Executing AD user creation script..."
              /tmp/set-password.sh
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
}

# Output the initial password (will be rotated by Vault)
output "vault_demo_initial_password" {
  description = "Initial password for vault-demo user (will be rotated by Vault)"
  value       = local.vault_demo_initial_password
  sensitive   = true
}
