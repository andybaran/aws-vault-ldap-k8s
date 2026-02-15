# Vault provider configuration
# Note: This requires the Vault provider to be configured in your root module
# The provider should point to the Vault service endpoint


# Secrets


resource "kubernetes_secret_v1" "vault-init-data" {
  metadata {
    name      = "vault-init-data"
    namespace = var.kube_namespace
  }
  type = "Opaque"
}

# Service Account for the Job
resource "kubernetes_service_account_v1" "secret_writer" {
  metadata {
    name      = "secret-writer-sa"
    namespace = var.kube_namespace
  }
}

# Role with permissions to manage secrets in the namespace
resource "kubernetes_role_v1" "secret_writer" {
  metadata {
    name      = "secret-writer-role"
    namespace = var.kube_namespace
  }

  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = ["vault-init-data"] # Only allow access to this specific secret
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
# resource "time_sleep" "wait_for_vault" {
#   depends_on      = [helm_release.vault_cluster]
#   create_duration = "60s"
# }

# Use Kubernetes exec to initialize Vault
resource "kubernetes_job_v1" "vault_init" {
  # depends_on = [time_sleep.wait_for_vault]

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
          image   = "${var.vault_image_repository}:${var.vault_image_tag}"
          command = ["/bin/sh", "-c"]
          args = [<<-EOT
            # Set Vault address to local pod
            export VAULT_ADDR=http://vault-0.vault-internal:8200

            # Get kubectl and jq first
            echo "Downloading kubectl and jq..."
            wget https://dl.k8s.io/release/v1.35.0/bin/linux/amd64/kubectl
            chmod +x kubectl
            wget https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-linux-amd64
            chmod +x jq-linux-amd64

            # Wait for Vault to be responsive
            until nc -z $(getent hosts vault-0.vault-internal | awk '{print $1}') 8200; do
              echo "Waiting for Vault..."
              sleep 2
            done

            # Check if already initialized
            if vault status | grep -q "Initialized.*false"; then
              # Initialize Vault
              vault operator init -key-shares=5 -key-threshold=3 -format=json > /tmp/init.json
              cat /tmp/init.json

              # Store init data in Kubernetes secret
              ./kubectl create secret generic vault-init-data --from-file=init.json=/tmp/init.json -n ${var.kube_namespace} --dry-run=client -o yaml | ./kubectl apply -f -

              # Unseal Vault using the keys
              UNSEAL_KEY_1=$(./jq-linux-amd64 -r '.unseal_keys_b64[0:1][]' /tmp/init.json)
              UNSEAL_KEY_2=$(./jq-linux-amd64 -r '.unseal_keys_b64[1:2][]' /tmp/init.json)
              UNSEAL_KEY_3=$(./jq-linux-amd64 -r '.unseal_keys_b64[2:3][]' /tmp/init.json)

              vault operator unseal $UNSEAL_KEY_1
              vault operator unseal $UNSEAL_KEY_2
              vault operator unseal $UNSEAL_KEY_3

              # Get root token for joining nodes
              ROOT_TOKEN=$(./jq-linux-amd64 -r '.root_token' /tmp/init.json)

              # Wait for vault-1 to be ready
              echo "Waiting for vault-1 to be ready..."
              until nc -z $(getent hosts vault-1.vault-internal | awk '{print $1}') 8200; do
                echo "Waiting for vault-1..."
                sleep 2
              done

              # Join vault-1 to the raft cluster
              echo "Joining vault-1 to raft cluster..."
              export VAULT_ADDR=http://vault-1.vault-internal:8200
              vault operator raft join http://vault-0.vault-internal:8200

              # Unseal vault-1
              echo "Unsealing vault-1..."
              vault operator unseal $UNSEAL_KEY_1
              vault operator unseal $UNSEAL_KEY_2
              vault operator unseal $UNSEAL_KEY_3

              # Wait for vault-2 to be ready
              echo "Waiting for vault-2 to be ready..."
              until nc -z $(getent hosts vault-2.vault-internal | awk '{print $1}') 8200; do
                echo "Waiting for vault-2..."
                sleep 2
              done

              # Join vault-2 to the raft cluster
              echo "Joining vault-2 to raft cluster..."
              export VAULT_ADDR=http://vault-2.vault-internal:8200
              vault operator raft join http://vault-0.vault-internal:8200

              # Unseal vault-2
              echo "Unsealing vault-2..."
              vault operator unseal $UNSEAL_KEY_1
              vault operator unseal $UNSEAL_KEY_2
              vault operator unseal $UNSEAL_KEY_3

              echo "Vault cluster initialized and all nodes joined successfully"
           else
             echo "Vault already initialized"

             # Check if vault-0, vault-1 and vault-2 need to be unsealed
             export VAULT_ADDR=http://vault-0.vault-internal:8200

             # Try to get the stored init data
             ./kubectl get secret vault-init-data -n ${var.kube_namespace} -o jsonpath='{.data.init\.json}' | base64 -d > /tmp/init.json

             UNSEAL_KEY_1=$(./jq-linux-amd64 -r '.unseal_keys_b64[0:1][]' /tmp/init.json)
             UNSEAL_KEY_2=$(./jq-linux-amd64 -r '.unseal_keys_b64[1:2][]' /tmp/init.json)
             UNSEAL_KEY_3=$(./jq-linux-amd64 -r '.unseal_keys_b64[2:3][]' /tmp/init.json)

             # Check and unseal vault-0 if needed
             echo "Checking vault-0 status..."
             if vault status | grep -q "Sealed.*true"; then
               echo "Unsealing vault-0..."
               vault operator unseal $UNSEAL_KEY_1
               vault operator unseal $UNSEAL_KEY_2
               vault operator unseal $UNSEAL_KEY_3
             else
               echo "vault-0 is already unsealed"
             fi

             # Check and unseal vault-1 if needed
             export VAULT_ADDR=http://vault-1.vault-internal:8200
             if nc -z $(getent hosts vault-1.vault-internal | awk '{print $1}') 8200; then
               echo "Checking vault-1 status..."
               if vault status | grep -q "Sealed.*true"; then
                 echo "Unsealing vault-1..."
                 vault operator unseal $UNSEAL_KEY_1
                 vault operator unseal $UNSEAL_KEY_2
                 vault operator unseal $UNSEAL_KEY_3
               else
                 echo "vault-1 is already unsealed"
               fi
             fi

             # Check and unseal vault-2 if needed
             export VAULT_ADDR=http://vault-2.vault-internal:8200
             if nc -z $(getent hosts vault-2.vault-internal | awk '{print $1}') 8200; then
               echo "Checking vault-2 status..."
               if vault status | grep -q "Sealed.*true"; then
                 echo "Unsealing vault-2..."
                 vault operator unseal $UNSEAL_KEY_1
                 vault operator unseal $UNSEAL_KEY_2
                 vault operator unseal $UNSEAL_KEY_3
               else
                 echo "vault-2 is already unsealed"
               fi
             fi
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


