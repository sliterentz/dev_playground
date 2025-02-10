resource "kubernetes_ingress_v1" "blue_green" {
  metadata {
    name        = "blue-green-ingress"
    namespace   = kubernetes_namespace.blue.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"               = "nginx"
      "cert-manager.io/cluster-issuer"            = "letsencrypt-${var.environment}"
    }
  }
  spec {
    rule {
      host = "app.${var.argocd_custom_domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.blue_green.metadata[0].name
              port {
                number = 9500
              }
            }
          }
        }
      }
    }
    tls {
      hosts       = ["app.${var.argocd_custom_domain}"]
      secret_name = "blue-green-tls"
    }
  }
}

resource "kubectl_manifest" "ingress_nginx" {
  count      = var.bind_ingress_port != "-" ? 1 : 0
  yaml_body  = templatefile("${path.module}/manifests/ingress-nginx.yaml", {
    environment           = var.environment
    argocd_server_domain  = var.argocd_custom_domain
    argocd_server_tls     = var.argocd_custom_tls
  })

  depends_on = [kubernetes_namespace.argocd]

  wait               = true
  server_side_apply  = true

  timeouts {
    create = "2m"
  }
}

# ArgoCD Server NodePort Service
resource "kubernetes_service" "argocd_server_nodeport" {
  metadata {
    name      = "argocd-server-nodeport"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = "argocd-server"
    }
    type = "NodePort"
    port {
      name        = "https"
      port        = 443
      target_port = 8080
      node_port   = 30443
    }
  }
  depends_on = [helm_release.argocd]

  timeouts {
    create = "15m"
  }
}

# Grafana LoadBalancer Service
resource "kubernetes_service" "grafana_lb" {
  metadata {
    name      = "grafana-lb"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = "grafana"
    }
    type = "LoadBalancer"
    port {
      port        = 80
      target_port = 3000
    }
  }
  depends_on = [helm_release.grafana]

  timeouts {
    create = "15m"
  }
}

# Loki LoadBalancer Service
resource "kubernetes_service" "loki_lb" {
  metadata {
    name      = "loki-lb"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = "loki"
    }
    type = "LoadBalancer"
    port {
      port        = 3100
      target_port = 3100
    }
  }
  depends_on = [helm_release.loki]

  timeouts {
    create = "15m"
  }
}

# Prometheus LoadBalancer Service
resource "kubernetes_service" "prometheus_lb" {
  metadata {
    name      = "prometheus-lb"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = "prometheus"
    }
    type = "LoadBalancer"
    port {
      port        = 9090
      target_port = 9090
    }
  }
  depends_on = [helm_release.prometheus_operator]
  
  timeouts {
    create = "15m"
  }
}

# Cert-manager ClusterIssuer
resource "kubectl_manifest" "cluster_issuer" {
  yaml_body = templatefile("${path.module}/manifests/cluster-issuer.yaml", {
    environment = var.environment
    acme_server = local.acme_server
    email       = var.cert_manager_email
  })

  depends_on = [helm_release.cert_manager]
}

# Ingress for ArgoCD
resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name        = "argocd-ingress"
    namespace   = kubernetes_namespace.argocd.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                    = "nginx"
      "cert-manager.io/cluster-issuer"                 = "letsencrypt-${var.environment}"
      "nginx.ingress.kubernetes.io/ssl-passthrough"    = "true"
      "nginx.ingress.kubernetes.io/backend-protocol"   = "HTTPS"
    }
  }
  spec {
    rule {
      host = var.argocd_custom_domain
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.argocd_server_nodeport.metadata[0].name
              port {
                number = 443
              }
            }
          }
        }
      }
    }
    tls {
      hosts       = [var.argocd_custom_domain]
      secret_name = var.argocd_custom_tls
    }
  }
  depends_on = [kubernetes_service.argocd_server_nodeport]
}

# Ingress for Grafana
resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name        = "grafana-ingress"
    namespace   = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                    = "nginx"
      "cert-manager.io/cluster-issuer"                 = "letsencrypt-${var.environment}"
    }
  }
  spec {
    rule {
      host = var.grafana_custom_domain
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "grafana"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
    tls {
      hosts       = [var.grafana_custom_domain]
      secret_name = var.grafana_custom_tls
    }
  }
  depends_on = [helm_release.grafana]
}