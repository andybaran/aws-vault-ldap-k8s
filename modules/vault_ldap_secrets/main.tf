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

# Dynamic role for generating time-bound AD accounts
# Reference: https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/ldap_secret_backend_dynamic_role
resource "vault_ldap_secret_backend_dynamic_role" "dynamicAD01" {
  mount     = vault_ldap_secret_backend.ad.path
  role_name = "dynamicAD01"

  creation_ldif = <<-LDIF
dn: CN={{.Username}},${var.ldap_userdn}
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: user
cn: {{.Username}}
sAMAccountName: {{.Username}}
userPrincipalName: {{.Username}}@${var.active_directory_domain}
unicodePwd: {{.Password}}
userAccountControl: 512
LDIF

  deletion_ldif = <<-LDIF
dn: CN={{.Username}},${var.ldap_userdn}
changetype: delete
LDIF

  default_ttl = 3600
  max_ttl     = 86400
}
