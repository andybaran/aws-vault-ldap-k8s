# resource "vault_policy" "apps_policy" {
#   namespace  = vault_namespace.namespace.path
#   name       = "apps-policy"

#   policy = <<EOT
# path "${vault_mount.credentials.path}/*" {
#   capabilities = ["create", "read", "update", "patch", "list"]
# }
# EOT
# }
