# Variables for windows_config module

variable "demo_id" {
  description = "Unique identifier for this demo instance"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster endpoint"
  type        = string
}

variable "kube_cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  type        = string
}

variable "kube_namespace" {
  description = "Kubernetes namespace for resources"
  type        = string
}

variable "ldap_dc_private_ip" {
  description = "Private IP address of the LDAP/AD domain controller"
  type        = string
}

variable "ldap_admin_password" {
  description = "LDAP administrator password"
  type        = string
  sensitive   = true
}
