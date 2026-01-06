# resource "time_sleep" "step_3" {
#   count = var.step_3 ? 1 : 0
#   depends_on = [
#     helm_release.nginx_ingress,
#     helm_release.vault_secrets_operator,
#     kubernetes_cluster_role_binding_v1.vault,
#     kubernetes_secret_v1.vault_token[0],
#     vault_kubernetes_auth_backend_role.simple_app_role[0],
#     vault_policy.apps_policy[0],
#   ]
#   create_duration  = "10s"
#   destroy_duration = "10s"
# }
