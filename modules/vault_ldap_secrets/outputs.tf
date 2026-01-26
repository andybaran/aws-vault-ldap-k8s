output "ldap_secrets_mount_path" {
  description = "The mount path of the LDAP secrets engine"
  value       =  vault_ldap_secret_backend.ad.path
}

output "ldap_secrets_mount_accessor" {
  description = "The accessor of the LDAP secrets engine mount"
  value       = vault_ldap_secret_backend.ad.accessor
}
