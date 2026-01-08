# Vault provider configuration
# Note: This requires the Vault provider to be configured in your root module
# The provider should point to the Vault service endpoint

# Wait for Vault pods to be ready
resource "time_sleep" "wait_for_vault" {
  depends_on      = [helm_release.vault_cluster]
  create_duration = "60s"
}

# Initialize Vault cluster
resource "vault_raft_autopilot" "vault_init" {
  depends_on = [time_sleep.wait_for_vault]

  # This resource requires Vault to be accessible
  # The actual initialization is handled by vault_init_unseal below
}

# Use Kubernetes exec to initialize Vault
resource "kubernetes_job_v1" "vault_init" {
  depends_on = [time_sleep.wait_for_vault]

  metadata {
    name      = "vault-init"
    namespace = var.kube_namespace
  }

  spec {
    template {
      metadata {}

      spec {
        service_account_name = "vault"
        restart_policy       = "Never"

        container {
          name    = "vault-init"
          image   = "hashicorp/vault-enterprise:1.21.2-ent"
          command = ["/bin/sh", "-c"]
          args = [<<-EOT
            # Set Vault address to local pod
            export VAULT_ADDR=http://vault-0.vault-internal:8200

            # Wait for Vault to be responsive
            until vault status 2>/dev/null; do
              echo "Waiting for Vault..."
              sleep 2
            done

            # Check if already initialized
            if vault status | grep -q "Initialized.*false"; then
              # Initialize Vault
              vault operator init -key-shares=5 -key-threshold=3 -format=json > /tmp/init.json

              # Store init data in Kubernetes secret
              kubectl create secret generic vault-init-keys \
                --from-file=init.json=/tmp/init.json \
                -n ${var.kube_namespace} \
                --dry-run=client -o yaml | kubectl apply -f -

              # Unseal Vault using the keys
              UNSEAL_KEY_1=$(cat /tmp/init.json | grep -o '"unseal_keys_b64":\["[^"]*"' | cut -d'"' -f4)
              UNSEAL_KEY_2=$(cat /tmp/init.json | grep -o '"unseal_keys_b64":\["[^"]*","[^"]*"' | cut -d'"' -f6)
              UNSEAL_KEY_3=$(cat /tmp/init.json | grep -o '"unseal_keys_b64":\["[^"]*","[^"]*","[^"]*"' | cut -d'"' -f8)

              vault operator unseal $UNSEAL_KEY_1
              vault operator unseal $UNSEAL_KEY_2
              vault operator unseal $UNSEAL_KEY_3

              echo "Vault initialized and unsealed successfully"
            else
              echo "Vault already initialized"
            fi
          EOT
          ]

          env {
            name  = "VAULT_ADDR"
            value = "http://vault-0.vault-internal:8200"
          }
        }
      }
    }

    backoff_limit = 4
  }

  wait_for_completion = true

  timeouts {
    create = "5m"
    update = "5m"
  }
}

# Retrieve the initialization keys from the secret
data "kubernetes_secret_v1" "vault_init_keys" {
  metadata {
    name      = "vault-init-keys"
    namespace = var.kube_namespace
  }

  depends_on = [kubernetes_job_v1.vault_init]
}

# Parse the JSON data
locals {
  vault_init_json = jsondecode(data.kubernetes_secret_v1.vault_init_keys.data["init.json"])
  unseal_keys_b64 = local.vault_init_json.unseal_keys_b64
  root_token      = local.vault_init_json.root_token
}
