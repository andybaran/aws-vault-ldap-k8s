output "ldap_secrets_mount_path" {
  description = "The mount path of the LDAP secrets engine"
  value       = vault_ldap_secret_backend.ad.path
}

output "ldap_secrets_mount_accessor" {
  description = "The accessor of the LDAP secrets engine mount"
  value       = vault_ldap_secret_backend.ad.accessor
}

output "static_role_name" {
  description = "The name of the LDAP static role"
  value       = vault_ldap_secret_backend_static_role.service_account.role_name
}

output "static_role_credentials_path" {
  description = "The full path to read static role credentials from Vault"
  value       = "${vault_ldap_secret_backend.ad.path}/static-cred/${vault_ldap_secret_backend_static_role.service_account.role_name}"
}

output "static_role_policy_name" {
  description = "The name of the policy for reading static role credentials"
  value       = vault_policy.ldap_static_read.name
}

output "static_role_rotation_period" {
  description = "The rotation period in seconds for the LDAP static role"
  value       = vault_ldap_secret_backend_static_role.service_account.rotation_period
}
