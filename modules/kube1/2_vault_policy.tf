resource "vault_policy" "apps_policy" {
  #count      = var.step_2 ? 1 : 0
  #depends_on = [time_sleep.step_2]
  namespace  = vault_namespace.namespace.path
  name       = "apps-policy"

  policy = <<EOT
path "${vault_mount.credentials.path}/*" {
  capabilities = ["create", "read", "update", "patch", "list"]
}
EOT
}
