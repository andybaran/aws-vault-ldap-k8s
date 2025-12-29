resource "vault_namespace" "namespace" {
  path = "${local.demo_id}-ns"
}
