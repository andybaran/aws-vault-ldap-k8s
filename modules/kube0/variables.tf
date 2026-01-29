variable "user_email" {
  type = string
  description = "e-mail address"
  default = "user@ibm.com"
}

variable "instance_type" {
  type = string
  description = "EKS worker node instance type"
  default = "t3.medium"
}

variable "customer_name" {
  type = string
  description = "Customer name"
}

variable "eks_node_ami_release_version" {
  type        = string
  description = "EKS managed node group AMI release version"
  default     = "1.34.2-20260128"
}