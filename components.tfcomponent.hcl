
component "kube0" {
  source = "./modules/kube0"
  inputs = {
    region                       = var.region
    customer_name                = var.customer_name
    user_email                   = var.user_email
    instance_type                = var.instance_type
    eks_node_ami_release_version = var.eks_node_ami_release_version
  }
  providers = {
    aws       = provider.aws.this
    random    = provider.random.this
    tls       = provider.tls.this
    null      = provider.null.this
    time      = provider.time.this
    cloudinit = provider.cloudinit.this
  }

}

component "kube1" {
  source = "./modules/kube1"
  inputs = {
    demo_id                                 = component.kube0.demo_id
    cluster_endpoint                        = component.kube0.cluster_endpoint
    kube_cluster_certificate_authority_data = component.kube0.kube_cluster_certificate_authority_data
    vault_license_key                       = var.vault_license_key
  }
  providers = {
    aws        = provider.aws.this
    kubernetes = provider.kubernetes.this
    helm       = provider.helm.this
    time       = provider.time.this
  }

}


component "vault_cluster" {
  source = "./modules/vault"
  inputs = {
    kube_namespace    = component.kube1.kube_namespace
    vault_image       = var.ldap_dual_account ? "ghcr.io/andybaran/vault-with-openldap-plugin:dual-account-rotation" : var.vault_image
    ldap_dual_account = var.ldap_dual_account
  }
  providers = {
    helm       = provider.helm.this
    kubernetes = provider.kubernetes.this
  }

}

# Active Directory domain controller — only created when ldap_provider = "ad"
component "ldap" {
  source = "./modules/AWS_DC"
  inputs = {
    allowlist_ip                    = var.allowlist_ip
    vpc_id                          = component.kube0.vpc_id
    subnet_id                       = component.kube0.first_public_subnet_id
    domain_controller_instance_type = var.instance_type
    shared_internal_sg_id           = component.kube0.shared_internal_sg_id
    prefix                = component.kube0.resources_prefix
    full_ui               = var.full_ui
    install_adds          = var.install_adds
    install_adcs          = var.install_adcs
    enabled               = var.ldap_provider == "ad"
  }
  providers = {
    aws    = provider.aws.this
    tls    = provider.tls.this
    random = provider.random.this
    time   = provider.time.this
  }

}

# OpenLDAP on EKS — only created when ldap_provider = "openldap"
component "openldap" {
  source = "./modules/openldap"
  inputs = {
    kube_namespace          = component.kube1.kube_namespace
    openldap_domain         = var.openldap_domain
    openldap_admin_password = var.openldap_admin_password
    prefix                  = component.kube0.resources_prefix
    enabled                 = var.ldap_provider == "openldap"
  }
  providers = {
    kubernetes = provider.kubernetes.this
    random     = provider.random.this
    time       = provider.time.this
  }
}

component "vault_ldap_secrets" {
  source = "./modules/vault_ldap_secrets"
  inputs = {
    # LDAP connection — switches between AD and OpenLDAP based on ldap_provider
    ldap_url      = var.ldap_provider == "ad" ? "ldaps://${component.ldap.dc-priv-ip}" : component.openldap.ldap_url
    ldap_binddn   = var.ldap_provider == "ad" ? "CN=Administrator,CN=Users,DC=mydomain,DC=local" : component.openldap.ldap_binddn
    ldap_bindpass = var.ldap_provider == "ad" ? component.ldap.password : component.openldap.ldap_bindpass
    ldap_userdn   = var.ldap_provider == "ad" ? "CN=Users,DC=mydomain,DC=local" : component.openldap.ldap_userdn
    ldap_schema   = var.ldap_provider == "ad" ? "ad" : "openldap"
    ldap_insecure_tls = var.ldap_provider == "ad" ? true : false

    secrets_mount_path          = "ldap"
    active_directory_domain     = var.ldap_provider == "ad" ? "mydomain.local" : var.openldap_domain
    kubernetes_host             = component.kube0.cluster_endpoint
    kubernetes_ca_cert          = component.kube0.kube_cluster_certificate_authority_data
    kube_namespace              = component.kube1.kube_namespace
    static_roles                = var.ldap_provider == "ad" ? component.ldap.static_roles : component.openldap.static_roles
    static_role_rotation_period = 100
    ldap_dual_account           = var.ldap_dual_account
    grace_period                = var.grace_period
  }
  providers = {
    vault = provider.vault.this
  }
}

component "ldap_app" {
  source = "./modules/ldap_app"
  inputs = {
    kube_namespace              = component.kube1.kube_namespace
    ldap_mount_path             = component.vault_ldap_secrets.ldap_secrets_mount_path
    ldap_static_role_name       = var.ldap_dual_account ? "dual-rotation-demo" : var.ldap_app_account_name
    vso_vault_auth_name         = component.vault_cluster.vso_vault_auth_name
    static_role_rotation_period = 100
    ldap_app_image              = var.ldap_app_image
    ldap_dual_account           = var.ldap_dual_account
    grace_period                = var.grace_period
    vault_app_auth_role         = component.vault_ldap_secrets.vault_app_auth_role_name
  }
  providers = {
    kubernetes = provider.kubernetes.this
    time       = provider.time.this
  }
}

# --- Stack Outputs ---

output "ldap_provider" {
  description = "Which LDAP backend is active: 'ad' or 'openldap'"
  value       = var.ldap_provider
  type        = string
}

output "public-dns-address" {
  description = "Public DNS address of the LDAP/DC instance (AD only)"
  value       = component.ldap.public-dns-address
  type        = string
}

output "ldap-eip-public-ip" {
  description = "Elastic IP public address for the LDAP/DC instance (AD only)"
  value       = component.ldap.eip-public-ip
  type        = string
}

output "ldap-private-ip" {
  description = "Private IP address of the LDAP/DC instance (AD only)"
  value       = component.ldap.dc-priv-ip
  type        = string
}

output "password" {
  description = "Admin password for the LDAP server"
  value       = var.ldap_provider == "ad" ? component.ldap.password : component.openldap.password
  type        = string
}

output "eks_cluster_name" {
  description = "The name of the EKS cluster."
  value       = component.kube0.eks_cluster_name
  type        = string
}

output "vault_service_name" {
  description = "The Vault service name."
  value       = component.vault_cluster.vault_service_name
  type        = string
}

output "vault_loadbalancer_hostname" {
  description = "Internal LoadBalancer hostname for Vault API"
  value       = component.vault_cluster.vault_loadbalancer_hostname
  type        = string
}

output "vault_ui_loadbalancer_hostname" {
  description = "Internal LoadBalancer hostname for Vault UI"
  value       = component.vault_cluster.vault_ui_loadbalancer_hostname
  type        = string
}

output "vault_root_token" {
  description = "Vault root token"
  value       = component.vault_cluster.vault_root_token
  type        = string
}

output "vault_ldap_secrets_path" {
  description = "Mount path for the Vault LDAP secrets engine"
  value       = component.vault_ldap_secrets.ldap_secrets_mount_path
  type        = string
}

output "ldap_app_service_name" {
  description = "Kubernetes service name for the LDAP credentials application"
  value       = component.ldap_app.ldap_app_service_name
  type        = string
}

output "ldap_app_access_info" {
  description = "Access information for the LDAP credentials application"
  value       = component.ldap_app.ldap_app_url
  type        = string
}

output "ldap_app_vault_agent_url" {
  description = "URL of the Vault Agent sidecar LDAP app"
  value       = component.ldap_app.ldap_app_vault_agent_url
  type        = string
}

output "ldap_app_csi_url" {
  description = "URL of the CSI Driver LDAP app"
  value       = component.ldap_app.ldap_app_csi_url
  type        = string
}
