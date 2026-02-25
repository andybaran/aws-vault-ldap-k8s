# Enable and configure the LDAP secrets engine for Active Directory
# Reference: https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/ldap_secret_backend
resource "vault_ldap_secret_backend" "ad" {
  count = var.ldap_dual_account ? 0 : 1

  path        = var.secrets_mount_path
  description = "LDAP secrets engine for Active Directory"

  # LDAP connection settings — use LDAPS (port 636) for encrypted connection.
  # AD requires TLS for password modifications; the DC has AD CS installed
  # which auto-enrolls a certificate enabling LDAPS.
  binddn   = var.ldap_binddn
  bindpass = var.ldap_bindpass
  url      = var.ldap_url

  # Accept the AD CS self-signed certificate (demo only)
  insecure_tls = true

  # Active Directory schema
  schema = "ad"

  # Use CN to search for users — the default for AD schema is userPrincipalName,
  # but Vault searches with the bare username (e.g., "vault-demo") which doesn't
  # match the full UPN ("vault-demo@mydomain.local"), causing 0 results.
  userattr = "cn"

  # User search base DN
  userdn = var.ldap_userdn

  # Enable rotation on import to populate last_vault_rotation timestamp
  # This ensures VSO receives valid static-creds metadata
  skip_static_role_import_rotation = false
}

# Static roles for managing password rotation of existing AD accounts.
# One Vault static role is created per entry in var.static_roles.
# Reference: https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/ldap_secret_backend_static_role
resource "vault_ldap_secret_backend_static_role" "roles" {
  for_each = var.ldap_dual_account ? {} : var.static_roles

  mount     = vault_ldap_secret_backend.ad[0].path
  role_name = each.key
  username  = each.value.username

  rotation_period = var.static_role_rotation_period

  # Allow initial rotation to import the password from AD
  skip_import_rotation = false
}

# Policy for reading LDAP static credentials — grants access to all static roles
# Reference: https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/policy
resource "vault_policy" "ldap_static_read" {
  name = "${var.secrets_mount_path}-static-read"

  policy = <<-EOT
    # Allow reading any static role credentials
    path "${var.secrets_mount_path}/static-cred/*" {
      capabilities = ["read"]
    }

    # Allow listing roles (optional, for discoverability)
    path "${var.secrets_mount_path}/static-role/*" {
      capabilities = ["list"]
    }
  EOT
}
