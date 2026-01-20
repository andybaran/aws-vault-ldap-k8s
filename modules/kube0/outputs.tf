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
  sensitive   = false
}

output "eks_cluster_name" {
  description = "The name of the EKS cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name}"
  sensitive   = false
}

output "eks_cluster_id" {
  description = "The ID of the EKS cluster."
  value       = module.eks.cluster_id 
  sensitive   = false 
}

output "eks_cluster_auth" {
  description = "The authentication token for the EKS cluster."
  value       = data.aws_eks_cluster_auth.eks_cluster_auth.token
  sensitive   = true
}

output "first_private_subnet_id" {
  description = "The first private subnet ID where the EKS cluster is deployed."
  value       = module.vpc.private_subnets[0]
  sensitive   = false
}

output "first_public_subnet_id" {
  description = "The first public subnet ID in the VPC."
  value       = module.vpc.public_subnets[0]
  sensitive   = false
}

output "shared_internal_sg_id" {
  description = "Security group ID for shared internal communication between admin VM and domain controller"
  value       = aws_security_group.shared_internal.id
  sensitive   = false
}