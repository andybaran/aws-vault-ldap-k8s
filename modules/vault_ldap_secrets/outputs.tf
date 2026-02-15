output "ldap_secrets_mount_path" {
  description = "The mount path of the LDAP secrets engine"
  value       = vault_ldap_secret_backend.ad.path
}

output "ldap_secrets_mount_accessor" {
  description = "The accessor of the LDAP secrets engine mount"
  value       = vault_ldap_secret_backend.ad.accessor
}

output "static_role_names" {
  description = "Map of all LDAP static role names"
  value       = { for k, v in vault_ldap_secret_backend_static_role.roles : k => v.role_name }
}

output "static_role_policy_name" {
  description = "The name of the policy for reading static role credentials"
  value       = vault_policy.ldap_static_read.name
}
