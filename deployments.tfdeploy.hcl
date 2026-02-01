store varset "aws_creds" {
  id       = "varset-oUu39eyQUoDbmxE1"
  category = "env"
}

store varset "vault_license" {
  id       = "varset-fMrcJCnqUd6q4D9C"
  category = "terraform"
}

deployment "development" {
  inputs = {
    region                = "us-east-2"
    customer_name         = "fidelity"
    user_email            = "andy.baran@hashicorp.com"
    instance_type         = "c5.xlarge"
    vault_license_key     = store.varset.vault_license.stable.vault_license_key
    eks_node_ami_release_version = "1.34.2-20260128"

    #### Auth credentials for AWS
    AWS_ACCESS_KEY_ID     = store.varset.aws_creds.AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY = store.varset.aws_creds.AWS_SECRET_ACCESS_KEY
    AWS_SESSION_TOKEN     = store.varset.aws_creds.AWS_SESSION_TOKEN
  }
  destroy = true
}
