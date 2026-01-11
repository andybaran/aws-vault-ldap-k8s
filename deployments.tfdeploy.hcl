store varset "aws_creds" {
  id       = "varset-oUu39eyQUoDbmxE1"
  category = "env"
}

store varset "vault_creds" {
  id       = "varset-kJh653kUmcUUNfzS"
  category = "env"
}

deployment "development" {
  inputs = {
    region                = "us-east-2"
    customer_name         = "fidelity"
    user_email            = "andy.baran@hashicorp.com"
    instance_type         = "m7i-flex.xlarge"
    vault_public_endpoint = "https://vault-cluster-public-vault-61ad1a65.ebf5a91e.z1.hashicorp.cloud:8200"

    #### Auth credentials for AWS
    AWS_ACCESS_KEY_ID     = store.varset.aws_creds.AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY = store.varset.aws_creds.AWS_SECRET_ACCESS_KEY
    AWS_SESSION_TOKEN     = store.varset.aws_creds.AWS_SESSION_TOKEN

    #### Auth credentials for Vault
    VAULT_TOKEN = store.varset.vault_creds.VAULT_TOKEN
    VAULT_ADDR  = store.varset.vault_creds.VAULT_ADDR

  }
  #destroy = true
}

