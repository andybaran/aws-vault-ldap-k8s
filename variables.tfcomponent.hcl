variable "customer_name" {
  description = "Specify the name of your customer. This helps to customize the resources created for your customer."
  type        = string
}


variable "region" {
  description = "The AWS region to use for this demo."
  type        = string
  default     = "us-east-2"
}

variable "instance_type" {
  description = "The EC2 instance type to use for the EKS worker nodes."
  type        = string
  default     = "t2.medium"
}

variable "vault_public_endpoint" {
  type    = string
  default = ""
}

variable "vault_root_namespace" {
  type    = string
  default = ""
}

variable "user_email" {
  type    = string
  default = ""
}

variable "AWS_ACCESS_KEY_ID" {
  description = "AWS access key"
  type        = string
  ephemeral   = true
}

variable "AWS_SECRET_ACCESS_KEY" {
  description = "AWS sensitive secret key."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "AWS_SESSION_TOKEN" {
  description = "AWS session token."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "vault_license_key" {
  description = "The Vault Enterprise license key."
  type        = string
  sensitive   = false
}