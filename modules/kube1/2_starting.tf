resource "time_sleep" "step_2" {
  depends_on = [
    vault_generic_secret.credentials,
  ]
  create_duration  = "10s"
  destroy_duration = "10s"
}
