# Outputs matching the interface expected by vault_ldap_secrets component.
# These provide the same data shape as the AWS_DC module so components
# can use ternary expressions to switch between providers.

output "ldap_url" {
  description = "LDAP URL for Vault secrets engine configuration"
  value       = var.enabled ? "ldap://openldap.${var.kube_namespace}.svc:389" : ""
  depends_on  = [time_sleep.wait_for_openldap]
}

output "ldap_binddn" {
  description = "Bind DN for Vault to authenticate to OpenLDAP"
  value       = var.enabled ? "cn=admin,${local.base_dn}" : ""
}

output "ldap_bindpass" {
  description = "Bind password for the admin account"
  value       = var.enabled ? var.openldap_admin_password : ""
  sensitive   = true
}

output "ldap_userdn" {
  description = "Base DN for user entries"
  value       = var.enabled ? local.user_ou_dn : ""
}

output "ldap_schema" {
  description = "LDAP schema for Vault secrets engine ('openldap')"
  value       = "openldap"
}

output "base_dn" {
  description = "Base DN derived from the domain"
  value       = var.enabled ? local.base_dn : ""
}

output "static_roles" {
  description = "Service account usernames, initial passwords, and DNs for Vault static roles"
  value = var.enabled ? {
    for name, pw in random_password.service_account_password : name => {
      username = name
      password = nonsensitive(pw.result)
      dn       = "cn=${name},ou=users,${local.base_dn}"
    }
  } : {}
  sensitive  = false
  depends_on = [time_sleep.wait_for_openldap]
}

# Legacy outputs for backwards compatibility with stack outputs
# These are AD-specific but must exist so the component doesn't error

output "dc-priv-ip" {
  description = "Not applicable for OpenLDAP — returns empty string"
  value       = ""
}

output "public-dns-address" {
  description = "Not applicable for OpenLDAP — returns empty string"
  value       = ""
}

output "eip-public-ip" {
  description = "Not applicable for OpenLDAP — returns empty string"
  value       = ""
}

output "password" {
  description = "Admin password for OpenLDAP (or empty if disabled)"
  value       = var.enabled ? nonsensitive(var.openldap_admin_password) : ""
}

output "openldap_service_name" {
  description = "Kubernetes service name for the OpenLDAP server"
  value       = var.enabled ? "openldap" : ""
}
