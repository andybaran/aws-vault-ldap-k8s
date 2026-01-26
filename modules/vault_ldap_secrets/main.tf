# Enable and configure the LDAP secrets engine for Active Directory
# Reference: https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/ldap_secret_backend
resource "vault_ldap_secret_backend" "ad" {
  path        = var.secrets_mount_path
  description = "LDAP secrets engine for Active Directory"

  # LDAP connection settings
  binddn   = var.ldap_binddn
  bindpass = var.ldap_bindpass
  url      = var.ldap_url

  # Active Directory schema
  schema = "ad"

  # User search base DN
  userdn = var.ldap_userdn

  # Do not rotate the administrator password on initial setup
  # Since we're using the main administrator account, we skip rotation
  skip_static_role_import_rotation = true
}
