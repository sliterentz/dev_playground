# Create a namespace for our application
resource "kubernetes_namespace" "dev-playground" {
  metadata {
    name = "dev-playground"
  }
}

# Create Minikube cluster
resource "kubernetes_deployment" "dev-playground" {
  metadata {
    name      = var.cluster_name
    labels    = {
      test = "simaster"
    }
    namespace = "dev-playground"
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        test = "simaster"
      }
    }

    template {
      metadata {
        labels = {
          test = "simaster"
        }
      }

      spec {
        container {
          image = "simaster-api:1.0.0"
          name  = "simaster"

          resources {
            limits = {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "50Mi"
            }
          }
        }
      }
    }
  }
}

# Create namespaces for blue-green deployment
resource "kubernetes_namespace" "blue" {
  metadata {
    name = "blue"
  }
}

resource "kubernetes_namespace" "green" {
  metadata {
    name = "green"
  }
}

# Blue-Green service
resource "kubernetes_service" "blue_green" {
  metadata {
    name      = "blue-green-service"
    namespace = kubernetes_namespace.blue.metadata[0].name
  }
  spec {
    selector = {
      app = "simaster-app"
    }
    port {
      port        = 9500
      target_port = 9500
    }
  }
}

# Minikube tunnel
resource "null_resource" "minikube_tunnel" {
  depends_on = [
    kubernetes_service.argocd_server_nodeport
  ]

  provisioner "local-exec" {
    command = <<-EOT
      nohup minikube tunnel > /dev/null 2>&1 &
      echo $! > minikube_tunnel.pid
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kill $(cat minikube_tunnel.pid)"
  }
}