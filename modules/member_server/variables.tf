variable "region" {
  type = string
  description = "The AWS region to deploy to."
  default = "us-east-2"
}

variable "prefix" {
  type = string
  description = "Prefix used to name various infrastructure components. Alphanumeric characters only."
  default     = "boundary-rdp"
}

variable "ami" {
  type = string
  description = "The AMI to use for the windows instances."
  default = "ami-0f92a5908d7b0f379"
}

variable "member_server_instance_type" {
  type = string
  description = "The AWS instance type to use for servers."
  default     = "m7i-flex.xlarge"
}

variable "root_block_device_size" {
  type = string
  description = "The volume size of the root block device."
  default     = 128
}

variable "active_directory_domain" {
  type = string 
  description = "The name of the Active Directory domain to be created on the Windows Domain Controller."
  default = "mydomain.local"
}

variable "active_directory_netbios_name" {
  type = string
  description = "Ostensibly the short-hand for the name of the domain."
  default = "mydomain"
}


variable "domain_controller_aws_keypair_name" {
  type = string
  description = "The AWS keypair created during creation of the domain controller."
}

// The following variables have values which are only known after deployment so we can't set sane defaults.

variable "domain_controller_ip" {
  type = string
  description = "IP Address of an already created Domain Controller and DNS server."
}

variable "domain_admin_password" {
  type = string
  description = "The domain administrator password."
}

variable "domain_controller_private_key" {
  type = string
  description = "The private key generated during creation of the domain controller."
}

variable "domain_controller_sec_group_id_list" {
  type = list
  description = "ID's of AWS Network Security Groups created during creation of the domain controller."
}

variable "prevent_NTLMv1" {
  type = bool
  description = "Enforce NTLMv2 by preventing NTLMv1"
  default = false
}
