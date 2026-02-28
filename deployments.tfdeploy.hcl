store varset "aws_creds" {
  id       = "varset-oUu39eyQUoDbmxE1"
  category = "env"
}

store varset "vault_license" {
  id       = "varset-fMrcJCnqUd6q4D9C"
  category = "terraform"
}

# deployment_auto_approve "successful_plans" {
#   check {
#     condition = context.success == true
#     reason    = "Operation failed and requires manual intervention."
#   }
# }

# deployment_group "auto_approve" {
#   auto_approve_checks = [
#     deployment_auto_approve.successful_plans,
#   ]
# }

deployment "development" {
  inputs = {
    region                = "us-east-2"
    customer_name         = "fidelity"
    user_email            = "andy.baran@hashicorp.com"
    instance_type         = "c5.xlarge"  # AMD64 instance type - container rebuilt for AMD64
    vault_license_key     = store.varset.vault_license.stable.vault_license_key
    eks_node_ami_release_version = "1.34.2-20260128"
    allowlist_ip                 = "66.190.197.168/32"
    ldap_dual_account            = true

    # Vault provider credentials - decoupled from vault_cluster component
    # outputs to avoid Stacks "unknown output" cascade during planning.
    # Update these in the "vault" variable set after vault re-initialization.
    vault_address = store.varset.vault_license.stable.vault_address
    vault_token   = store.varset.vault_license.stable.vault_token

    #### Auth credentials for AWS
    AWS_ACCESS_KEY_ID     = store.varset.aws_creds.AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY = store.varset.aws_creds.AWS_SECRET_ACCESS_KEY
    AWS_SESSION_TOKEN     = store.varset.aws_creds.AWS_SESSION_TOKEN
  }
  #destroy = true
  # deployment_group = deployment_group.auto_approve
}



# Re-trigger: previous apply had transient EKS token expiry + identity change
