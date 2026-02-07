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

# ClusterRole with permissions to manage VPC CNI and monitor Windows nodes
resource "kubernetes_cluster_role_v1" "vpc_cni_manager" {
  metadata {
    name = "${var.kube_namespace}-vpc-cni-manager"
  }

  # Manage VPC CNI DaemonSet
  rule {
    api_groups     = ["apps"]
    resources      = ["daemonsets"]
    resource_names = ["aws-node"]
    verbs          = ["get", "list", "patch", "update"]
  }

  # Read nodes to check Windows node readiness
  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list"]
  }

  # Manage amazon-vpc-cni ConfigMap for Windows IPAM enablement
  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "create", "update", "patch"]
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

# Job 1: Enable Windows IPAM in VPC CNI and wait for Windows nodes
# This MUST complete before any Windows pods can be scheduled
resource "kubernetes_job_v1" "windows_k8s_config" {
  metadata {
    name      = "windows-k8s-config"
    namespace = var.kube_namespace
  }

  wait_for_completion = true

  timeouts {
    create = "20m"
    update = "20m"
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
            wget -q https://dl.k8s.io/release/v1.35.0/bin/linux/amd64/kubectl
            chmod +x kubectl

            # ================================================
            # Step 1: Enable Windows IPAM via ConfigMap
            # Per AWS docs: https://docs.aws.amazon.com/eks/latest/userguide/windows-support.html
            # ================================================
            echo "================================================"
            echo "Step 1: Enabling Windows IPAM via ConfigMap"
            echo "================================================"

            # Check if ConfigMap already exists with correct value
            CURRENT_VALUE=$(./kubectl get configmap amazon-vpc-cni -n kube-system -o jsonpath='{.data.enable-windows-ipam}' 2>/dev/null || echo "")

            if [ "$CURRENT_VALUE" = "true" ]; then
              echo "✓ Windows IPAM already enabled in ConfigMap"
            else
              echo "Creating/updating amazon-vpc-cni ConfigMap..."
              cat <<'CMEOF' | ./kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: amazon-vpc-cni
  namespace: kube-system
data:
  enable-windows-ipam: "true"
CMEOF

              # Verify ConfigMap was applied
              UPDATED_VALUE=$(./kubectl get configmap amazon-vpc-cni -n kube-system -o jsonpath='{.data.enable-windows-ipam}')
              if [ "$UPDATED_VALUE" = "true" ]; then
                echo "✓ Windows IPAM enabled via ConfigMap"
              else
                echo "✗ ERROR: Failed to enable Windows IPAM in ConfigMap"
                exit 1
              fi
            fi

            # Also set DaemonSet env as a belt-and-suspenders approach
            echo "Setting ENABLE_WINDOWS_IPAM on DaemonSet as well..."
            ./kubectl set env daemonset/aws-node -n kube-system ENABLE_WINDOWS_IPAM=true 2>/dev/null || true

            # ================================================
            # Step 2: Wait for VPC CNI DaemonSet rollout
            # ================================================
            echo "================================================"
            echo "Step 2: Waiting for VPC CNI DaemonSet rollout..."
            echo "================================================"

            for i in $(seq 1 30); do
              DESIRED=$(./kubectl get daemonset aws-node -n kube-system -o jsonpath='{.status.desiredNumberScheduled}')
              UPDATED=$(./kubectl get daemonset aws-node -n kube-system -o jsonpath='{.status.updatedNumberScheduled}' 2>/dev/null || echo "0")
              AVAILABLE=$(./kubectl get daemonset aws-node -n kube-system -o jsonpath='{.status.numberAvailable}')

              echo "  DaemonSet: Desired=$DESIRED Updated=$UPDATED Available=$AVAILABLE"

              if [ "$DESIRED" = "$UPDATED" ] && [ "$DESIRED" = "$AVAILABLE" ] && [ -n "$DESIRED" ] && [ "$DESIRED" != "0" ]; then
                echo "✓ VPC CNI DaemonSet rollout complete"
                break
              fi

              if [ $i -eq 30 ]; then
                echo "⚠ WARNING: DaemonSet rollout timed out, proceeding anyway"
              fi

              sleep 10
            done

            # ================================================
            # Step 3: Wait for Windows nodes to join and be Ready
            # Windows managed node groups may take several minutes to launch
            # ================================================
            echo "================================================"
            echo "Step 3: Waiting for Windows nodes to join cluster..."
            echo "================================================"

            for i in $(seq 1 60); do
              WINDOWS_NODE_COUNT=$(./kubectl get nodes -l kubernetes.io/os=windows --no-headers 2>/dev/null | wc -l | tr -d ' ')

              if [ "$WINDOWS_NODE_COUNT" -gt 0 ]; then
                echo "✓ Found $WINDOWS_NODE_COUNT Windows node(s)"
                break
              fi

              if [ $i -eq 60 ]; then
                echo "✗ ERROR: No Windows nodes found after 10 minutes"
                echo "Dumping all nodes for debugging:"
                ./kubectl get nodes -o wide --show-labels
                exit 1
              fi

              echo "  Waiting for Windows nodes to join... (attempt $i/60)"
              sleep 10
            done

            # Wait for Windows nodes to be Ready
            echo "Checking Windows node readiness..."
            WINDOWS_NODE_COUNT=$(./kubectl get nodes -l kubernetes.io/os=windows --no-headers 2>/dev/null | wc -l | tr -d ' ')

            for i in $(seq 1 60); do
              READY_COUNT=$(./kubectl get nodes -l kubernetes.io/os=windows -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c "True" || echo "0")
              echo "  Windows nodes Ready: $READY_COUNT/$WINDOWS_NODE_COUNT"

              if [ "$READY_COUNT" -ge 1 ]; then
                echo "✓ At least one Windows node is Ready"
                break
              fi

              if [ $i -eq 60 ]; then
                echo "✗ ERROR: No Windows nodes became Ready after 10 minutes"
                echo "Dumping node status for debugging:"
                ./kubectl describe nodes -l kubernetes.io/os=windows
                exit 1
              fi

              sleep 10
            done

            # ================================================
            # Step 4: Wait for Windows networking to be fully initialized
            # The vpc-resource-controller needs time to allocate IPs
            # ================================================
            echo "================================================"
            echo "Step 4: Verifying Windows networking readiness..."
            echo "================================================"

            echo "Waiting 60 seconds for vpc-resource-controller to allocate IPs to Windows nodes..."
            sleep 60

            echo "✓ Windows IPAM configuration and node readiness verified"
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
  ldap_server         = var.ldap_dc_private_ip
  ldap_admin_dn       = "CN=Administrator,CN=Users,DC=mydomain,DC=local"
  vault_demo_username = "vault-demo"
  # Use the same password as the Administrator account for complexity compliance.
  # Vault will rotate this immediately after the LDAP secrets engine is configured.
  vault_demo_initial_password = var.ldap_admin_password
  ad_tools_image              = "ghcr.io/andybaran/aws-vault-ldap-k8s/ad-tools:ltsc2022"
}

# Secret containing credentials and config for AD user creation
resource "kubernetes_secret_v1" "ldap_admin_creds" {
  metadata {
    name      = "ldap-admin-creds"
    namespace = var.kube_namespace
  }

  data = {
    admin_dn         = local.ldap_admin_dn
    admin_password   = var.ldap_admin_password
    ad_server        = local.ldap_server
    vault_user       = local.vault_demo_username
    initial_password = local.vault_demo_initial_password
  }

  type = "Opaque"
}

# ConfigMap with PowerShell script for creating the vault-demo user in Active Directory
# NOTE: This script uses NO Terraform interpolation — all dynamic values come via env vars.
# This prevents special characters in passwords from corrupting PowerShell syntax.
resource "kubernetes_config_map_v1" "create_ad_user_script" {
  metadata {
    name      = "create-ad-user-script"
    namespace = var.kube_namespace
  }

  data = {
    "Create-ADUser.ps1" = <<-'EOT'
      # PowerShell script to create vault-demo user in Active Directory
      # All dynamic values are passed via environment variables to avoid
      # Terraform interpolation issues with special characters in passwords.

      $ErrorActionPreference = "Stop"

      $ADServer = $env:AD_SERVER
      $VaultUser = $env:VAULT_USER
      $InitialPassword = $env:INITIAL_PASSWORD
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
      $AdminUsername = ($env:ADMIN_DN -replace 'CN=([^,]+),.*','$1')
      $DomainName = "mydomain"
      $Credential = New-Object System.Management.Automation.PSCredential("$DomainName\$AdminUsername", $AdminPassword)

      Write-Host "Admin User: $DomainName\$AdminUsername"

      # Wait for AD server to be ready
      Write-Host "Waiting for AD server to be ready..."
      $Connected = $false
      for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
          $TestResult = Test-NetConnection -ComputerName $ADServer -Port 389 -InformationLevel Quiet -WarningAction SilentlyContinue
          if ($TestResult) {
            Write-Host "AD server is reachable on port 389"
            $Connected = $true
            break
          }
        } catch {
          # Connection failed, will retry
        }

        if ($i -eq $MaxRetries) {
          Write-Host "ERROR: AD server not reachable after $MaxRetries attempts"
          Write-Host "Network debugging:"
          try { Resolve-DnsName $ADServer } catch { Write-Host "DNS resolution failed" }
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
        Write-Host "Active Directory module loaded successfully"
      } catch {
        Write-Host "ERROR: Failed to load Active Directory module"
        Write-Host $_.Exception.Message
        exit 1
      }

      # Test AD authentication
      Write-Host "Testing AD authentication..."
      try {
        $null = Get-ADDomain -Server $ADServer -Credential $Credential -ErrorAction Stop
        Write-Host "AD authentication successful"
      } catch {
        Write-Host "ERROR: AD authentication failed"
        Write-Host $_.Exception.Message
        exit 1
      }

      # Check if user already exists
      Write-Host "Checking if user $VaultUser already exists..."
      try {
        $ExistingUser = Get-ADUser -Identity $VaultUser -Server $ADServer -Credential $Credential -ErrorAction SilentlyContinue
        if ($ExistingUser) {
          Write-Host "User $VaultUser already exists - removing for fresh start (demo mode)"
          try {
            Remove-ADUser -Identity $VaultUser -Server $ADServer -Credential $Credential -Confirm:$false -ErrorAction Stop
            Write-Host "Existing user deleted successfully"
            Start-Sleep -Seconds 2
          } catch {
            Write-Host "Warning: Failed to delete existing user"
            Write-Host $_.Exception.Message
          }
        } else {
          Write-Host "User $VaultUser does not exist, proceeding with creation"
        }
      } catch {
        Write-Host "User $VaultUser does not exist, proceeding with creation"
      }

      # Create user with password
      Write-Host "Creating user $VaultUser with password..."
      try {
        $SecurePassword = ConvertTo-SecureString -String $InitialPassword -AsPlainText -Force

        $NewUserParams = @{
          Name                  = $VaultUser
          SamAccountName        = $VaultUser
          UserPrincipalName     = "$VaultUser@mydomain.local"
          DisplayName           = "Vault Demo Service Account"
          Description           = "Service account managed by HashiCorp Vault for password rotation demo"
          AccountPassword       = $SecurePassword
          Enabled               = $true
          PasswordNeverExpires  = $false
          ChangePasswordAtLogon = $false
          Server                = $ADServer
          Credential            = $Credential
          Path                  = "CN=Users,DC=mydomain,DC=local"
          ErrorAction           = "Stop"
        }
        New-ADUser @NewUserParams

        Write-Host "User created successfully with password and enabled"
      } catch {
        Write-Host "Failed to create user"
        Write-Host $_.Exception.Message
        exit 1
      }

      # Verify user was created
      Write-Host "Verifying user creation..."
      try {
        $CreatedUser = Get-ADUser -Identity $VaultUser -Server $ADServer -Credential $Credential -Properties Enabled,PasswordNeverExpires -ErrorAction Stop
        Write-Host "User verification successful"
        Write-Host ("  SamAccountName: " + $CreatedUser.SamAccountName)
        Write-Host ("  DistinguishedName: " + $CreatedUser.DistinguishedName)
        Write-Host ("  Enabled: " + $CreatedUser.Enabled)
        Write-Host ("  PasswordNeverExpires: " + $CreatedUser.PasswordNeverExpires)
      } catch {
        Write-Host "Warning: User verification failed"
        Write-Host $_.Exception.Message
      }

      # Test user authentication
      Write-Host "Testing user authentication with new password..."
      try {
        $TestPassword = ConvertTo-SecureString -String $InitialPassword -AsPlainText -Force
        $TestCredential = New-Object System.Management.Automation.PSCredential("$DomainName\$VaultUser", $TestPassword)
        $null = Get-ADDomain -Server $ADServer -Credential $TestCredential -ErrorAction Stop
        Write-Host "User authentication successful - password is working"
      } catch {
        Write-Host "Warning: User authentication test failed (may need replication time)"
        Write-Host $_.Exception.Message
      }

      Write-Host "==============================================="
      Write-Host "AD User Creation Job Completed Successfully"
      Write-Host ("User: " + $VaultUser)
      Write-Host ("DN: " + $UserDN)
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
    create = "20m"
    update = "20m"
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
          image = local.ad_tools_image

          command = ["powershell", "-ExecutionPolicy", "Bypass", "-File", "C:\\scripts\\Create-ADUser.ps1"]

          env {
            name = "AD_SERVER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.ldap_admin_creds.metadata[0].name
                key  = "ad_server"
              }
            }
          }

          env {
            name = "VAULT_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.ldap_admin_creds.metadata[0].name
                key  = "vault_user"
              }
            }
          }

          env {
            name = "INITIAL_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.ldap_admin_creds.metadata[0].name
                key  = "initial_password"
              }
            }
          }

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
