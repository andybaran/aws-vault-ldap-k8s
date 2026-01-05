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