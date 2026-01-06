output "vpc_id" {
  description = "The VPC ID where the EKS cluster is deployed."
  value       = module.vpc.vpc_id
  sensitive   = false
}

output "demo_id" {
  description = "The demo identifier."
  value       = local.demo_id
  sensitive   = false
}

output "cluster_endpoint" {
  description = "The endpoint for the EKS cluster."
  value       = module.eks.cluster_endpoint
  sensitive   = false
}

output "kube_cluster_certificate_authority_data" {
  description = "Kube cluster CA data"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}