# Vault provider configuration
# Note: This requires the Vault provider to be configured in your root module
# The provider should point to the Vault service endpoint


# Secrets
resource "kubernetes_secret_v1" "vault_license" {
data = {
    license = base64encode(var.vault_license_key)
}
  metadata {
    name      = "vault-license"
    namespace = var.kube_namespace
}
}

resource "kubernetes_secret_v1" "vault-init-data" {
  metadata {
    name      = "vault-init-data"
    namespace = var.kube_namespace
}
}

# Service Account for the Job
resource "kubernetes_service_account_v1" "secret_writer" {
  metadata {
    name      = "secret-writer-sa"
    namespace = var.kube_namespace
  }
}

# Role with permissions to manage secrets
resource "kubernetes_role_v1" "secret_writer" {
  metadata {
    name      = "secret-writer-role"
    namespace = var.kube_namespace
  }

  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = ["vault-init-data"]  # Only allow access to this specific secret
    verbs          = ["get", "create", "update", "patch"]
  }
}

# RoleBinding to bind the ServiceAccount to the Role
resource "kubernetes_role_binding_v1" "secret_writer" {
  metadata {
    name      = "secret-writer-binding"
    namespace = var.kube_namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.secret_writer.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.secret_writer.metadata[0].name
    namespace = var.kube_namespace
  }
}



# Wait for Vault pods to be ready
resource "time_sleep" "wait_for_vault" {
  depends_on      = [helm_release.vault_cluster]
  create_duration = "60s"
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
        service_account_name = kubernetes_service_account_v1.secret_writer.metadata[0].name
        restart_policy       = "Never"

        container {
          name    = "vault-init"
          image   = "hashicorp/vault-enterprise:1.21.2-ent"
          command = ["/bin/sh", "-c"]
          args = [<<-EOT
            # Set Vault address to local pod
            export VAULT_ADDR=http://vault-0.vault-internal:8200

            # Wait for Vault to be responsive
            until nc -z $(getent hosts vault-0.vault-internal | awk '{print $1}') 8200; do
              echo "Waiting for Vault..."
              sleep 2
            done

            # Check if already initialized
            if vault status | grep -q "Initialized.*false"; then
              # Initialize Vault
              vault operator init -key-shares=5 -key-threshold=3 -format=json > /tmp/init.json

              # Get JQ 
              wget https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-linux-amd64
              chmod +x jq-linux-amd64

              # Store init data in Kubernetes secret
              kubectl create secret generic ${kubernetes_secret_v1.vault-init-data.metadata[0].name} \
                --from-file=init.json=/tmp/init.json \
                -n ${var.kube_namespace} \
                --dry-run=client -o yaml | kubectl apply -f -

              # Unseal Vault using the keys
              UNSEAL_KEY_1=$(./jq-linux-amd64 -r '.unseal_keys_b64[0:1][]' init.json)
              UNSEAL_KEY_2=$(./jq-linux-amd64 -r '.unseal_keys_b64[1:2][]' init.json)
              UNSEAL_KEY_3=$(./jq-linux-amd64 -r '.unseal_keys_b64[2:3][]' init.json)

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
  vault_init_json = jsondecode(data.kubernetes_secret_v1.vault_init_keys.data)
  unseal_keys_b64 = local.vault_init_json.unseal_keys_b64
  root_token      = local.vault_init_json.root_token
}
