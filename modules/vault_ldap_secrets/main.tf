# Enable the LDAP secrets engine
resource "vault_mount" "ldap" {
  path        = var.secrets_mount_path
  type        = "ldap"
  description = "LDAP secrets engine for Active Directory"
}

# Configure the LDAP secrets engine for Active Directory
resource "vault_ldap_secret_backend_config" "ad" {
  mount    = vault_mount.ldap.path
  schema   = "ad"
  url      = var.ldap_url
  binddn   = var.ldap_binddn
  bindpass = var.ldap_bindpass
  userdn   = var.ldap_userdn

  # Do not rotate the administrator password
  # The rotate-root endpoint should NOT be called for this configuration
  # since we're using the main administrator account
}
