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