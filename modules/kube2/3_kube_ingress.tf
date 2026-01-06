resource "kubernetes_ingress_v1" "apps" {
  #count = var.step_3 ? 1 : 0
  depends_on = [
    #time_sleep.step_3,
    kubernetes_service_v1.static_app,
  ]
  metadata {
    name      = "simple-app"
    namespace = var.kube_namespace
    annotations = {
      "kubernetes.io/ingress.class"              = "nginx"
      "ingress.kubernetes.io/ssl-redirect"       = "false"
      "nginx.ingress.kubernetes.io/ssl-redirect" = "false"
      "nginx.ingress.kubernetes.io/use-regex"    = "true"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.static_app.metadata.0.name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}
