

component "ldap" {
    source = "./modules/AWS_DC"
    inputs = {
        region = var.region
        prefix = var.customer_name
        allowlist_ip = "66.190.197.168/32"
        vpc_id = component.kube0.outputs.vpc_id
    }
    providers = {
        aws = provider.aws.this
        tls = provider.tls.this
        random = provider.random.this
    }

}

    output "public-dns-address" {
        description = "This is the public DNS address of our instance"
        value = component.ldap.public-dns-address
        type = string
        ephemeral = false
        sensitive = false
    }
    output "password" {
        description = "This is the decrypted administrator password for the EC2 instance"
        value = component.ldap.password
        ephemeral = false
        sensitive = false
        type = string

    }