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

variable "prefix" {
  description = "Prefix for naming resources"
  type        = string
}

variable "key_name" {
  description = "Name of the AWS key pair to use for the admin VM"
  type        = string
}

variable "ssh_private_key" {
  description = "Private SSH key for connecting to the admin VM"
  type        = string
  sensitive   = true
}
