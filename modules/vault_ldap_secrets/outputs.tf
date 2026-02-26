output "ldap_secrets_mount_path" {
  description = "The mount path of the LDAP secrets engine"
  value       = var.secrets_mount_path
}

output "ldap_secrets_mount_accessor" {
  description = "The accessor of the LDAP secrets engine mount"
  value       = var.ldap_dual_account ? try(vault_mount.ldap_dual_account[0].accessor, "") : vault_ldap_secret_backend.ad[0].accessor
}

output "static_role_names" {
  description = "Map of all LDAP static role names"
  value = var.ldap_dual_account ? {
    (var.dual_account_static_role_name) = var.dual_account_static_role_name
  } : { for k, v in vault_ldap_secret_backend_static_role.roles : k => v.role_name }
}

output "static_role_policy_name" {
  description = "The name of the policy for reading static role credentials"
  value       = vault_policy.ldap_static_read.name
}

output "vault_app_auth_role_name" {
  description = "Vault K8s auth role name for the LDAP app to poll directly"
  value       = var.ldap_dual_account ? "ldap-app-role" : ""
}
