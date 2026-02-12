variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "allowlist_ip" {
  type = string
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "region" {
  type = string
}

variable "eks_cluster_name" {
  type = string
}

variable "vault_namespace" {
  type = string
}

variable "vault_service_name" {
  type    = string
  default = "vault"
}

variable "shared_internal_sg_id" {
  type = string
}

variable "prefix" {
  type = string
}

variable "key_name" {
  type = string
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}
