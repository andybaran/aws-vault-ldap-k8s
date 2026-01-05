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
        kubernetes = provider.kubernetes.this
        helm = provider.helm.this
        random = provider.random.this
        tls = provider.tls.this
        null = provider.null.this
        time = provider.time.this
        cloudinit = provider.cloudinit.this
        vault = provider.vault.this
    }

}

/* output "cluster_endpoint" {
    description = "The endpoint for the EKS cluster."
    value = component.kube0.cluster_endpoint 
    type = string
    ephemeral = false
    sensitive = falseß
} */

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