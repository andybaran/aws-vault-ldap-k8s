variable "allowlist_ip" {
  type        = string
  description = "IP to allow access for the security groups."
}

variable "prefix" {
  type        = string
  description = "Prefix used to name various infrastructure components. Alphanumeric characters only."
  default     = "boundary-rdp"
}

variable "aws_key_pair_name" {
  type        = string
  description = "key_name for the aws_key_pair resource"
  default     = "RDPKey"
}

variable "ami" {
  type        = string
  description = "The AMI to use for the windows instances."
  default     = "ami-08f787888f20cc63c"
}

variable "domain_controller_instance_type" {
  type        = string
  description = "The AWS instance type to use for servers."
  default     = "m7i-flex.xlarge"
}

variable "root_block_device_size" {
  type        = string
  description = "The volume size of the root block device."
  default     = 128
}

variable "active_directory_domain" {
  type        = string
  description = "The name of the Active Directory domain to be created on the Windows Domain Controller."
  default     = "mydomain.local"
}

variable "active_directory_netbios_name" {
  type        = string
  description = "Ostensibly the short-hand for the name of the domain."
  default     = "mydomain"
}

variable "only_ntlmv2" {
  type        = bool
  description = "Only use NTLMv2"
  default     = false
}

variable "only_kerberos" {
  type        = bool
  description = "Only allow kerberos auth"
  default     = false
}

variable "vpc_id" {
  type        = string
  description = "The VPC ID where the LDAP server will be deployed."
}

variable "subnet_id" {
  type        = string
  description = "The Subnet ID where the LDAP server will be deployed."
}

variable "shared_internal_sg_id" {
  description = "Security group ID for shared internal communication"
  type        = string
}