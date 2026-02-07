# Kubernetes Job to create the vault-demo user in Active Directory
# This job runs once after DC provisioning to create the user that Vault will manage

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
    namespace = kubernetes_namespace_v1.simple_app.metadata[0].name
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
    namespace = kubernetes_namespace_v1.simple_app.metadata[0].name
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
          name = "create-ad-user"
          # Windows Server Core with PowerShell and AD tools
          # ltsc2022 = Long-Term Servicing Channel 2022 (stable)
          image = "mcr.microsoft.com/powershell:lts-windowsservercore-ltsc2022"

          # PowerShell command to run the script
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

# Output the initial password (will be rotated by Vault)
output "vault_demo_initial_password" {
  description = "Initial password for vault-demo user (will be rotated by Vault)"
  value       = local.vault_demo_initial_password
  sensitive   = true
}
