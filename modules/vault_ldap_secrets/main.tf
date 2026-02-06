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

# Static role for managing password rotation of an existing AD account
# Reference: https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/ldap_secret_backend_static_role
resource "vault_ldap_secret_backend_static_role" "service_account" {
  mount     = vault_ldap_secret_backend.ad.path
  role_name = var.static_role_name
  username  = var.static_role_username

  # Rotate password every 24 hours (86400 seconds)
  rotation_period = var.static_role_rotation_period

  # Allow initial rotation to import the password from AD
  # This is required for Vault to manage and return the credentials
  skip_import_rotation = false
}

# Policy for reading LDAP static credentials
# Reference: https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/policy
resource "vault_policy" "ldap_static_read" {
  name = "${var.secrets_mount_path}-static-read"

  policy = <<-EOT
    # Allow reading static role credentials
    path "${vault_ldap_secret_backend.ad.path}/static-cred/${vault_ldap_secret_backend_static_role.service_account.role_name}" {
      capabilities = ["read"]
    }

    # Allow listing roles (optional, for discoverability)
    path "${vault_ldap_secret_backend.ad.path}/static-role/*" {
      capabilities = ["list"]
    }
  EOT
}
