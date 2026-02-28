# Dual-Account (Blue/Green) LDAP Secrets Engine Configuration
# These resources are only created when ldap_dual_account = true.
# They register and configure a custom Vault plugin that supports
# dual-account rotation with grace periods.

# Register the custom plugin in Vault's plugin catalog
resource "vault_generic_endpoint" "register_plugin" {
  count = var.ldap_dual_account ? 1 : 0

  path = "sys/plugins/catalog/secret/ldap_dual_account"

  disable_read   = true
  disable_delete = false

  data_json = jsonencode({
    sha256  = var.plugin_sha256
    command = "vault-plugin-secrets-openldap"
    version = "v0.17.0-dual-account.1"
  })
}

# Mount the custom plugin as a secrets engine
resource "vault_mount" "ldap_dual_account" {
  count = var.ldap_dual_account ? 1 : 0

  path        = var.secrets_mount_path
  type        = "ldap_dual_account"
  description = "Dual-account LDAP secrets engine for Active Directory"

  depends_on = [vault_generic_endpoint.register_plugin]
}

# Configure the LDAP backend connection
resource "vault_generic_endpoint" "ldap_config" {
  count = var.ldap_dual_account ? 1 : 0

  path = "${var.secrets_mount_path}/config"

  disable_read   = true
  disable_delete = true

  data_json = jsonencode({
    binddn       = var.ldap_binddn
    bindpass     = var.ldap_bindpass
    url          = var.ldap_url
    schema       = "ad"
    insecure_tls = true
    userattr     = "cn"
    userdn       = var.ldap_userdn
  })

  depends_on = [vault_mount.ldap_dual_account]
}

# Create dual-account static role with svc-rotate-a (primary) and svc-rotate-b (secondary)
resource "vault_generic_endpoint" "ldap_dual_static_role" {
  count = var.ldap_dual_account ? 1 : 0

  path = "${var.secrets_mount_path}/static-role/${var.dual_account_static_role_name}"

  disable_read   = true
  disable_delete = false

  data_json = jsonencode({
    username          = "svc-rotate-a"
    dn                = "CN=svc-rotate-a,CN=Users,DC=mydomain,DC=local"
    username_b        = "svc-rotate-b"
    dn_b              = "CN=svc-rotate-b,CN=Users,DC=mydomain,DC=local"
    rotation_period   = "${var.static_role_rotation_period}s"
    dual_account_mode = true
    grace_period      = "${var.grace_period}s"
  })

  depends_on = [vault_generic_endpoint.ldap_config]
}

# Single-account static roles for svc-single and svc-lib
# The custom dual-account plugin also supports standard single-account static roles
resource "vault_generic_endpoint" "ldap_single_static_role" {
  for_each = var.ldap_dual_account ? {
    "svc-single" = {
      username = "svc-single"
      dn       = "CN=svc-single,CN=Users,DC=mydomain,DC=local"
    }
    "svc-lib" = {
      username = "svc-lib"
      dn       = "CN=svc-lib,CN=Users,DC=mydomain,DC=local"
    }
  } : {}

  path           = "${var.secrets_mount_path}/static-role/${each.key}"
  disable_read   = true
  disable_delete = false

  data_json = jsonencode({
    username        = each.value.username
    dn              = each.value.dn
    rotation_period = "${var.static_role_rotation_period}s"
  })

  depends_on = [vault_generic_endpoint.ldap_config]
}
