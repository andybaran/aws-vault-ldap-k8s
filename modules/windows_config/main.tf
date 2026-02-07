# Windows Configuration Module
# This module handles Windows-specific Kubernetes configuration:
# 1. Enables Windows IPAM in VPC CNI (required for Windows node pools)
# 2. Creates the vault-demo AD user (requires Windows IPAM to be enabled first)

# Service Account for the jobs
resource "kubernetes_service_account_v1" "windows_config" {
  metadata {
    name      = "windows-config-sa"
    namespace = var.kube_namespace
  }
}

# ClusterRole with permissions to manage VPC CNI DaemonSet in kube-system
resource "kubernetes_cluster_role_v1" "vpc_cni_manager" {
  metadata {
    name = "${var.kube_namespace}-vpc-cni-manager"
  }

  rule {
    api_groups     = ["apps"]
    resources      = ["daemonsets"]
    resource_names = ["aws-node"]
    verbs          = ["get", "list", "patch", "update"]
  }
}

# ClusterRoleBinding to grant the service account VPC CNI management permissions
resource "kubernetes_cluster_role_binding_v1" "vpc_cni_manager" {
  metadata {
    name = "${var.kube_namespace}-vpc-cni-manager-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.vpc_cni_manager.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.windows_config.metadata[0].name
    namespace = var.kube_namespace
  }
}

# Job 1: Enable Windows IPAM in VPC CNI
# This MUST run first, before any Windows pods can be scheduled
resource "kubernetes_job_v1" "windows_k8s_config" {
  metadata {
    name      = "windows-k8s-config"
    namespace = var.kube_namespace
  }

  wait_for_completion = true

  timeouts {
    create = "15m"
    update = "15m"
  }

  spec {
    ttl_seconds_after_finished = 3600

    template {
      metadata {
        labels = {
          app = "windows-k8s-config"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.windows_config.metadata[0].name
        restart_policy       = "Never"

        container {
          name    = "enable-windows-ipam"
          image   = "hashicorp/vault-enterprise:1.21.2-ent"
          command = ["/bin/sh", "-c"]
          args = [<<-EOT
            # Get kubectl
            echo "Downloading kubectl..."
            wget https://dl.k8s.io/release/v1.35.0/bin/linux/amd64/kubectl
            chmod +x kubectl

            # Enable Windows IPAM for VPC CNI (required for Windows pods)
            echo "================================================"
            echo "Enabling Windows IPAM in VPC CNI"
            echo "================================================"
            
            # Wait for aws-node DaemonSet to exist
            echo "Waiting for VPC CNI aws-node DaemonSet..."
            for i in $(seq 1 30); do
              if ./kubectl get daemonset aws-node -n kube-system >/dev/null 2>&1; then
                echo "✓ aws-node DaemonSet found"
                break
              fi
              if [ $i -eq 30 ]; then
                echo "✗ ERROR: Timeout waiting for aws-node DaemonSet"
                exit 1
              fi
              echo "  Waiting... (attempt $i/30)"
              sleep 10
            done

            # Check if Windows IPAM is already enabled
            echo "Checking current Windows IPAM status..."
            CURRENT_VALUE=$(./kubectl get daemonset aws-node -n kube-system -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_WINDOWS_IPAM")].value}' 2>/dev/null || echo "")
            
            if [ "$CURRENT_VALUE" = "true" ]; then
              echo "✓ Windows IPAM already enabled"
            else
              echo "Enabling Windows IPAM..."
              ./kubectl set env daemonset/aws-node -n kube-system ENABLE_WINDOWS_IPAM=true
              
              # Verify the change
              echo "Verifying Windows IPAM is enabled..."
              UPDATED_VALUE=$(./kubectl get daemonset aws-node -n kube-system -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_WINDOWS_IPAM")].value}')
              if [ "$UPDATED_VALUE" = "true" ]; then
                echo "✓ Windows IPAM enabled successfully"
              else
                echo "✗ ERROR: Failed to verify Windows IPAM setting"
                exit 1
              fi
            fi

            # Wait for DaemonSet rollout to complete
            echo "================================================"
            echo "Waiting for VPC CNI DaemonSet rollout..."
            echo "================================================"
            
            for i in $(seq 1 30); do
              # Check DaemonSet rollout status
              DESIRED=$(./kubectl get daemonset aws-node -n kube-system -o jsonpath='{.status.desiredNumberScheduled}')
              UPDATED=$(./kubectl get daemonset aws-node -n kube-system -o jsonpath='{.status.updatedNumberScheduled}')
              AVAILABLE=$(./kubectl get daemonset aws-node -n kube-system -o jsonpath='{.status.numberAvailable}')
              
              echo "DaemonSet status: Desired=$DESIRED, Updated=$UPDATED, Available=$AVAILABLE"
              
              if [ "$DESIRED" = "$UPDATED" ] && [ "$DESIRED" = "$AVAILABLE" ] && [ -n "$DESIRED" ] && [ "$DESIRED" != "0" ]; then
                echo "✓ VPC CNI DaemonSet rollout complete"
                break
              fi
              
              if [ $i -eq 30 ]; then
                echo "⚠ WARNING: DaemonSet rollout did not complete in time"
                echo "Proceeding anyway - Windows nodes may need additional time"
              fi
              
              echo "  Waiting for rollout... (attempt $i/30)"
              sleep 10
            done

            # Additional wait for Windows nodes to initialize with new IPAM config
            # Windows networking initialization takes longer than Linux
            echo "================================================"
            echo "Waiting for Windows nodes to initialize..."
            echo "================================================"
            
            # Check if Windows nodes exist
            WINDOWS_NODE_COUNT=$(./kubectl get nodes -l kubernetes.io/os=windows --no-headers 2>/dev/null | wc -l)
            echo "Found $WINDOWS_NODE_COUNT Windows node(s)"
            
            if [ "$WINDOWS_NODE_COUNT" -gt 0 ]; then
              # Wait for Windows nodes to be Ready
              echo "Checking Windows node readiness..."
              for i in $(seq 1 30); do
                READY_COUNT=$(./kubectl get nodes -l kubernetes.io/os=windows -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | grep -c "True" || echo "0")
                echo "  Windows nodes ready: $READY_COUNT/$WINDOWS_NODE_COUNT"
                
                if [ "$READY_COUNT" = "$WINDOWS_NODE_COUNT" ]; then
                  echo "✓ All Windows nodes are Ready"
                  break
                fi
                
                if [ $i -eq 30 ]; then
                  echo "⚠ WARNING: Not all Windows nodes ready"
                fi
                
                sleep 10
              done
              
              # Give Windows IPAM additional time to fully initialize
              # Windows CNI configuration is slower than Linux
              echo "Allowing additional time for Windows IPAM initialization..."
              sleep 30
              
              echo "✓ Windows nodes initialization wait completed"
            else
              echo "⚠ No Windows nodes found - skipping readiness check"
              echo "Windows pods may fail if nodes are not yet joined to the cluster"
            fi

            echo "✓ Windows IPAM configuration completed"
            echo "================================================"
          EOT
          ]
        }
      }
    }

    backoff_limit = 4
  }
}

# Locals for AD user creation
locals {
  ldap_server                 = var.ldap_dc_private_ip
  ldap_admin_dn               = "CN=Administrator,CN=Users,DC=mydomain,DC=local"
  vault_demo_username         = "vault-demo"
  vault_demo_initial_password = "VaultDemo123!" # Will be rotated by Vault immediately
}

# Secret containing LDAP admin credentials for user creation
resource "kubernetes_secret_v1" "ldap_admin_creds" {
  metadata {
    name      = "ldap-admin-creds"
    namespace = var.kube_namespace
  }

  data = {
    admin_dn       = local.ldap_admin_dn
    admin_password = var.ldap_admin_password
  }

  type = "Opaque"
}

# ConfigMap with PowerShell script for creating the vault-demo user in Active Directory
resource "kubernetes_config_map_v1" "create_ad_user_script" {
  metadata {
    name      = "create-ad-user-script"
    namespace = var.kube_namespace
  }

  data = {
    "Create-ADUser.ps1" = <<-EOT
      # PowerShell script to create vault-demo user in Active Directory
      # Uses native AD cmdlets - simpler and more reliable than LDAP tools
      
      $ErrorActionPreference = "Stop"
      
      $ADServer = "${local.ldap_server}"
      $VaultUser = "${local.vault_demo_username}"
      $InitialPassword = "${local.vault_demo_initial_password}"
      $UserDN = "CN=$VaultUser,CN=Users,DC=mydomain,DC=local"
      $MaxRetries = 30
      $RetryDelay = 10
      
      Write-Host "==============================================="
      Write-Host "AD User Creation Job Starting (PowerShell)"
      Write-Host "AD Server: $ADServer"
      Write-Host "User: $VaultUser"
      Write-Host "User DN: $UserDN"
      Write-Host "Method: Native AD PowerShell cmdlets"
      Write-Host "==============================================="
      
      # Build credential object from environment variables
      $AdminPassword = ConvertTo-SecureString -String $env:ADMIN_PASSWORD -AsPlainText -Force
      $AdminUsername = ($env:ADMIN_DN -replace 'CN=([^,]+),.*','$1')  # Extract username from DN
      $DomainName = "mydomain"  # Domain name for credentials
      $Credential = New-Object System.Management.Automation.PSCredential("$DomainName\$AdminUsername", $AdminPassword)
      
      Write-Host "Admin User: $DomainName\$AdminUsername"
      
      # Wait for AD server to be ready
      Write-Host "Waiting for AD server to be ready..."
      $Connected = $false
      for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
          # Test connection using Test-NetConnection (built-in, no extra modules needed)
          $TestResult = Test-NetConnection -ComputerName $ADServer -Port 389 -InformationLevel Quiet -WarningAction SilentlyContinue
          if ($TestResult) {
            Write-Host "✓ AD server is reachable on port 389"
            $Connected = $true
            break
          }
        } catch {
          # Connection failed, will retry
        }
        
        if ($i -eq $MaxRetries) {
          Write-Host "✗ ERROR: AD server not reachable after $MaxRetries attempts"
          Write-Host "Network debugging:"
          Write-Host "- Testing DNS resolution:"
          try { Resolve-DnsName $ADServer } catch { Write-Host "DNS resolution failed: $_" }
          Write-Host "- Testing connectivity:"
          Test-NetConnection -ComputerName $ADServer -Port 389 -InformationLevel Detailed
          exit 1
        }
        
        Write-Host "Waiting for AD server... (attempt $i/$MaxRetries)"
        Start-Sleep -Seconds $RetryDelay
      }
      
      # Additional wait for AD service to be fully initialized
      Write-Host "Waiting 10 seconds for AD service to fully initialize..."
      Start-Sleep -Seconds 10
      
      # Import Active Directory module
      Write-Host "Loading Active Directory PowerShell module..."
      try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-Host "✓ Active Directory module loaded successfully"
      } catch {
        Write-Host "✗ ERROR: Failed to load Active Directory module: $_"
        Write-Host "This container may not have the AD PowerShell tools installed."
        exit 1
      }
      
      # Test AD authentication
      Write-Host "Testing AD authentication..."
      try {
        # Try to query AD - this will fail if credentials are wrong
        $null = Get-ADDomain -Server $ADServer -Credential $Credential -ErrorAction Stop
        Write-Host "✓ AD authentication successful"
      } catch {
        Write-Host "✗ ERROR: AD authentication failed: $_"
        exit 1
      }
      
      # Check if user already exists
      Write-Host "Checking if user $VaultUser already exists..."
      try {
        $ExistingUser = Get-ADUser -Identity $VaultUser -Server $ADServer -Credential $Credential -ErrorAction SilentlyContinue
        if ($ExistingUser) {
          Write-Host "✓ User $VaultUser already exists - removing for fresh start (demo mode)"
          try {
            Remove-ADUser -Identity $VaultUser -Server $ADServer -Credential $Credential -Confirm:$false -ErrorAction Stop
            Write-Host "✓ Existing user deleted successfully"
            Start-Sleep -Seconds 2  # Give AD time to process deletion
          } catch {
            Write-Host "⚠ Warning: Failed to delete existing user: $_"
            Write-Host "Will attempt to create anyway..."
          }
        } else {
          Write-Host "✓ User $VaultUser does not exist, proceeding with creation"
        }
      } catch {
        Write-Host "✓ User $VaultUser does not exist, proceeding with creation"
      }
      
      # Create user with password in one operation
      Write-Host "Creating user $VaultUser with password..."
      Write-Host "Note: Using New-ADUser cmdlet (native AD, no LDIF/LDAPS complexity)"
      
      try {
        $SecurePassword = ConvertTo-SecureString -String $InitialPassword -AsPlainText -Force
        
        New-ADUser `
          -Name $VaultUser `
          -SamAccountName $VaultUser `
          -UserPrincipalName "$VaultUser@mydomain.local" `
          -DisplayName "Vault Demo Service Account" `
          -Description "Service account managed by HashiCorp Vault for password rotation demo" `
          -AccountPassword $SecurePassword `
          -Enabled $true `
          -PasswordNeverExpires $false `
          -ChangePasswordAtLogon $false `
          -Server $ADServer `
          -Credential $Credential `
          -Path "CN=Users,DC=mydomain,DC=local" `
          -ErrorAction Stop
        
        Write-Host "✓ User created successfully with password and enabled"
      } catch {
        Write-Host "✗ Failed to create user: $_"
        Write-Host "Error details: $($_.Exception.Message)"
        exit 1
      }
      
      # Verify user was created
      Write-Host "Verifying user creation..."
      try {
        $CreatedUser = Get-ADUser -Identity $VaultUser -Server $ADServer -Credential $Credential -Properties Enabled,PasswordNeverExpires -ErrorAction Stop
        Write-Host "✓ User verification successful"
        Write-Host "  - SamAccountName: $($CreatedUser.SamAccountName)"
        Write-Host "  - DistinguishedName: $($CreatedUser.DistinguishedName)"
        Write-Host "  - Enabled: $($CreatedUser.Enabled)"
        Write-Host "  - PasswordNeverExpires: $($CreatedUser.PasswordNeverExpires)"
      } catch {
        Write-Host "⚠ Warning: User verification failed: $_"
      }
      
      # Test user authentication (validates password is set correctly)
      Write-Host "Testing user authentication with new password..."
      try {
        $TestPassword = ConvertTo-SecureString -String $InitialPassword -AsPlainText -Force
        $TestCredential = New-Object System.Management.Automation.PSCredential("$DomainName\$VaultUser", $TestPassword)
        
        # Try to query AD with the new user's credentials
        $null = Get-ADDomain -Server $ADServer -Credential $TestCredential -ErrorAction Stop
        Write-Host "✓ User authentication successful - password is working"
      } catch {
        Write-Host "⚠ Warning: User authentication test failed: $_"
        Write-Host "This may be normal if account needs time to replicate"
      }
      
      Write-Host "==============================================="
      Write-Host "✓ AD User Creation Job Completed Successfully"
      Write-Host "User: $VaultUser"
      Write-Host "DN: $UserDN"
      Write-Host "Initial password: $InitialPassword"
      Write-Host "Note: This password will be rotated by Vault"
      Write-Host "==============================================="
    EOT
  }
}

# Job 2: Create AD user
# This job depends on Windows IPAM being enabled (Job 1)
resource "kubernetes_job_v1" "create_ad_user" {
  # Wait for Windows IPAM to be enabled first
  depends_on = [kubernetes_job_v1.windows_k8s_config]

  metadata {
    name      = "create-ad-user"
    namespace = var.kube_namespace
  }

  wait_for_completion = true

  timeouts {
    create = "10m"
    update = "10m"
  }

  spec {
    ttl_seconds_after_finished = 3600

    template {
      metadata {
        labels = {
          app = "create-ad-user"
        }
      }

      spec {
        restart_policy = "OnFailure"

        # Windows nodes required for Windows containers
        node_selector = {
          "kubernetes.io/os" = "windows"
        }

        # Tolerate Windows node taints
        toleration {
          key      = "os"
          operator = "Equal"
          value    = "windows"
          effect   = "NoSchedule"
        }

        container {
          name  = "create-ad-user"
          image = "mcr.microsoft.com/powershell:lts-windowsservercore-ltsc2022"

          command = ["pwsh", "-Command"]
          args = [
            <<-EOT
              Write-Host "Starting AD user creation job..."
              Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"
              Write-Host "OS: $($PSVersionTable.OS)"
              
              # Execute the PowerShell script from ConfigMap
              & C:\scripts\Create-ADUser.ps1
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
            name       = "scripts"
            mount_path = "C:\\scripts"
          }
        }

        volume {
          name = "scripts"
          config_map {
            name = kubernetes_config_map_v1.create_ad_user_script.metadata[0].name
            items {
              key  = "Create-ADUser.ps1"
              path = "Create-ADUser.ps1"
            }
          }
        }
      }
    }
  }
}
