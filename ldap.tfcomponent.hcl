

component "ldap" {
    source = "/modules/AWS_DC"
    inputs = {
        region = var.region
        prefix = var.customer_name
        allowlist_ip = "${component.public_ip.my_ip_addr}/32"
    }
    providers = {
        aws = provider.aws.this
        tls = provider.tls.this
        random = provider.random.this
    }

}

    output "public-dns-address" {
        description = "This is the public DNS address of our instance"
        value = module.AWS-DC.public-dns-address
        type = string
        ephemeral = false
        sensitive = false
    }
    output "password" {
        description = "This is the decrypted administrator password for the EC2 instance"
        value = module.AWS-DC.password
        ephemeral = false
        sensitive = false
        type = string

    }