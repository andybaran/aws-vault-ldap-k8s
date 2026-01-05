component "kube1" {
    source = "./modules/kube1"
    inputs = {
        vault_public_endpoint = var.vault_public_endpoint
        customer_name = var.customer_name
        user_email = var.user_email
        instance_type = var.instance_type
    }
    providers = {
        aws = provider.aws.this
        kubernetes = provider.kubernetes.this
        helm = provider.helm.this
        time = provider.time.this
        vault = provider.vault.this
    }

}