component "kube0" {
    source = "./modules/kube0"
    inputs = {
        region = var.region
        customer_name = var.customer_name
        user_email = var.user_email
        instance_type = var.instance_type
    }
    providers = {
        aws = provider.aws.this
      #  kubernetes = provider.kubernetes.this
     #   helm = provider.helm.this
        random = provider.random.this
        tls = provider.tls.this
        null = provider.null.this
        time = provider.time.this
        cloudinit = provider.cloudinit.this
     #   vault = provider.vault.this
    }

}

output "vpc_id" {
    description = "The VPC ID where the EKS cluster is deployed."
    value = component.kube0.vpc_id
    type = string
    ephemeral = false
    sensitive = false
}

output "demo_id" {
    description = "The demo identifier."
    value = component.kube0.demo_id
    type = string
    ephemeral = false
    sensitive = false
}

output "cluster_endpoint" {
    description = "The endpoint for the EKS cluster."
    value = component.kube0.cluster_endpoint
    type = string
    ephemeral = false
    sensitive = false
}

output "kube_cluster_certificate_authority_data" {
    description = "Kube cluster CA data"
    value = component.kube0.kube_cluster_certificate_authority_data
    type = string
    ephemeral = false
    sensitive = true
}


component "kube1" {
    source = "./modules/kube1"
    inputs = {
        customer_name = var.customer_name
        user_email = var.user_email
        instance_type = var.instance_type
        vault_public_endpoint = var.vault_public_endpoint
        demo_id = component.kube0.demo_id
        cluster_endpoint = component.kube0.cluster_endpoint
        kube_cluster_certificate_authority_data = component.kube0.kube_cluster_certificate_authority_data
        eks_cluster_name = component.kube0.eks_cluster_name
    }
    providers = {
        aws = provider.aws.this
        kubernetes = provider.kubernetes.this
        helm = provider.helm.this
        time = provider.time.this
        vault = provider.vault.this
    }

}

component "kube2" {
    source = "./modules/kube2"
    inputs = {
        kube_namespace = component.kube1.kube_namespace
    }
    providers = {
        kubernetes = provider.kubernetes.this
    }

}


component "ldap" {
    source = "./modules/AWS_DC"
    inputs = {
        region = var.region
        prefix = var.customer_name
        allowlist_ip = "66.190.197.168/32"
        vpc_id = component.kube0.vpc_id
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

