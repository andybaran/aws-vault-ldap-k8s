variable "vpc_id" {
  description = "The ID of the VPC where the admin VM will be deployed"
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet where the admin VM will be deployed"
  type        = string
}

variable "instance_type" {
  description = "The EC2 instance type for the admin VM"
  type        = string
}

variable "allowlist_ip" {
  description = "The IP CIDR block allowed to SSH into the admin VM"
  type        = string
}

variable "environment" {
  description = "Environment name for resource naming"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region for the EKS cluster"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster to administer"
  type        = string
}

variable "vault_namespace" {
  description = "Kubernetes namespace where Vault is deployed"
  type        = string
}

variable "vault_service_name" {
  description = "Name of the Vault service in Kubernetes"
  type        = string
  default     = "vault"
}

variable "shared_internal_sg_id" {
  description = "Security group ID for shared internal communication"
  type        = string
}

# variable "vault_loadbalancer_hostname" {
#   description = "Internal LoadBalancer hostname for Vault API"
#   type        = string
# }

# variable "vault_ui_loadbalancer_hostname" {
#   description = "Internal LoadBalancer hostname for Vault UI"
#   type        = string
# }
