variable "customer_name" {
  description = "Specify the name of your customer. This helps to customize the resources created for your customer."
  type        = string

  #validation {
  #  condition     = length(var.customer_name) <= 50 && can(regex("^[a-z0-9-]*$", var.customer_name))
  #  error_message = "Customer name must be 50 characters or less and can only contain lowercase letters, numbers, and hyphens"
  #}
}


variable "region" {
  description = "The AWS region to use for this demo."
  type        = string
  default     = "us-west-2"
}

variable "step_2" {
  description = "Set to `true` once initial run is complete."
  type        = bool
  default     = false
}

variable "step_3" {
  description = "Set to `true` once `step_2` run is complete."
  type        = bool
  default     = false
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

variable "VAULT_TOKEN" {
  description = "Vault access token."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "VAULT_ADDR" {
  description = "Vault address."
  type        = string
  ephemeral   = true
}