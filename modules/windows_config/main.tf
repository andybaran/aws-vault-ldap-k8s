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
# The script is loaded from an external file to avoid Terraform/HCL interpolation
# conflicts with PowerShell $ variables and special characters in passwords.
resource "kubernetes_config_map_v1" "create_ad_user_script" {
  metadata {
    name      = "create-ad-user-script"
    namespace = var.kube_namespace
  }

  data = {
    "Create-ADUser.ps1" = file("${path.module}/scripts/Create-ADUser.ps1")
  }
}

# Job 2: Create AD user
# This job depends on Windows IPAM being enabled (Job 1)
# The job is replaced whenever the DC credentials secret changes (e.g., DC rebuild
# produces a new IP or password), ensuring the vault-demo user is always created
# on the current domain controller.
resource "kubernetes_job_v1" "create_ad_user" {
  # Wait for Windows IPAM to be enabled first
  depends_on = [kubernetes_job_v1.windows_k8s_config]

  metadata {
    name      = "create-ad-user"
    namespace = var.kube_namespace
    annotations = {
      # Force job re-creation when the DC is rebuilt — the private IP changes
      # on each new instance, so a change here triggers Terraform to destroy
      # the old completed job and create a new one.
      "demo/dc-private-ip" = var.ldap_dc_private_ip
    }
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
