output "vpc_id" {
  description = "The VPC ID where the EKS cluster is deployed."
  value       = module.vpc.vpc_id
  sensitive   = false
}