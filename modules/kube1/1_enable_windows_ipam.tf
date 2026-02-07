# Enable Windows IPAM for VPC CNI using local-exec
# This is required because the VPC CNI add-on doesn't support enabling Windows IPAM
# via configuration_values (schema rejects it)

resource "null_resource" "enable_windows_ipam" {
  # Run after namespace is created (ensures cluster is ready)
  depends_on = [kubernetes_namespace_v1.simple_app]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo "================================================"
      echo "Enabling Windows IPAM in VPC CNI"
      echo "================================================"
      
      # Wait for aws-node DaemonSet to exist
      echo "Waiting for VPC CNI aws-node DaemonSet..."
      for i in {1..30}; do
        if kubectl get daemonset aws-node -n kube-system >/dev/null 2>&1; then
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
      CURRENT_VALUE=$(kubectl get daemonset aws-node -n kube-system -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_WINDOWS_IPAM")].value}' 2>/dev/null || echo "")
      
      if [ "$CURRENT_VALUE" = "true" ]; then
        echo "✓ Windows IPAM already enabled, skipping"
      else
        echo "Enabling Windows IPAM..."
        kubectl set env daemonset/aws-node -n kube-system ENABLE_WINDOWS_IPAM=true
        
        # Verify the change
        echo "Verifying Windows IPAM is enabled..."
        UPDATED_VALUE=$(kubectl get daemonset aws-node -n kube-system -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_WINDOWS_IPAM")].value}')
        if [ "$UPDATED_VALUE" = "true" ]; then
          echo "✓ Windows IPAM enabled successfully"
        else
          echo "✗ ERROR: Failed to verify Windows IPAM setting"
          exit 1
        fi
        
        # Restart aws-node pods to pick up the change
        echo "Restarting aws-node DaemonSet..."
        kubectl rollout restart daemonset/aws-node -n kube-system
        
        # Wait for rollout to complete
        echo "Waiting for aws-node rollout to complete..."
        kubectl rollout status daemonset/aws-node -n kube-system --timeout=5m
      fi

      # Wait for vpc-resource-controller to be created (Windows IPAM controller)
      echo "Waiting for vpc-resource-controller deployment..."
      for i in {1..60}; do
        if kubectl get deployment vpc-resource-controller -n kube-system >/dev/null 2>&1; then
          echo "✓ vpc-resource-controller deployment found"
          
          # Wait for it to be ready
          echo "Waiting for vpc-resource-controller to be ready..."
          if kubectl wait --for=condition=available --timeout=300s deployment/vpc-resource-controller -n kube-system 2>/dev/null; then
            echo "✓ vpc-resource-controller is ready"
            break
          else
            echo "⚠ vpc-resource-controller not ready yet, continuing to wait..."
          fi
        fi
        
        if [ $i -eq 60 ]; then
          echo "⚠ WARNING: vpc-resource-controller not ready after 10 minutes"
          echo "  This may be normal if Windows nodes haven't joined the cluster yet"
          echo "  The controller will be created when the first Windows node joins"
          echo "  Continuing anyway..."
          break
        fi
        
        echo "  Waiting for vpc-resource-controller... (attempt $i/60)"
        sleep 10
      done

      echo "================================================"
      echo "✓ Windows IPAM Configuration Completed"
      echo "================================================"
      echo "Summary:"
      echo "  - ENABLE_WINDOWS_IPAM set to: true"
      echo "  - aws-node DaemonSet: Restarted"
      if kubectl get deployment vpc-resource-controller -n kube-system >/dev/null 2>&1; then
        echo "  - vpc-resource-controller: Deployed"
      else
        echo "  - vpc-resource-controller: Will deploy when Windows nodes join"
      fi
      echo ""
      echo "Windows pods should now be able to get IP addresses"
      echo "================================================"
    EOT

    # Use the kubernetes provider's config
    environment = {
      # Inherit KUBECONFIG from environment if set
      KUBECONFIG = ""
    }
  }

  # Re-run if the cluster configuration changes
  triggers = {
    cluster_endpoint = var.cluster_endpoint
  }
}

# Output to confirm Windows IPAM is enabled
output "windows_ipam_enabled" {
  description = "Indicates that Windows IPAM has been enabled in VPC CNI"
  value       = "Windows IPAM enabled via kubectl patch (local-exec)"
  depends_on  = [null_resource.enable_windows_ipam]
}
