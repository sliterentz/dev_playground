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

# PostgreSQL StatefulSet
resource "kubernetes_stateful_set" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.blue.metadata[0].name
  }

  spec {
    service_name = "postgres"
    replicas     = 1

    selector {
      match_labels = {
        app = "postgres"
      }
    }

    template {
      metadata {
        labels = {
          app = "postgres"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:13"

          env {
            name  = "POSTGRES_DB"
            value = "simaster"
          }
          env {
            name = "POSTGRES_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_secrets.metadata[0].name
                key  = "postgres-user"
              }
            }
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_secrets.metadata[0].name
                key  = "postgres-password"
              }
            }
          }

          port {
            container_port = 5432
          }

          volume_mount {
            name       = "postgres-storage"
            mount_path = "/var/lib/postgresql/data"
            sub_path   = "postgres"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "postgres-storage"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "1Gi"
          }
        }
      }
    }
  }
}

# MongoDB StatefulSet
resource "kubernetes_stateful_set" "mongodb" {
  metadata {
    name      = "mongodb"
    namespace = kubernetes_namespace.blue.metadata[0].name
  }

  spec {
    service_name = "mongodb"
    replicas     = 1

    selector {
      match_labels = {
        app = "mongodb"
      }
    }

    template {
      metadata {
        labels = {
          app = "mongodb"
        }
      }

      spec {
        container {
          name  = "mongodb"
          image = "mongo:4.4"

          env {
            name = "MONGO_INITDB_ROOT_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.mongodb_secrets.metadata[0].name
                key  = "mongodb-root-username"
              }
            }
          }
          env {
            name = "MONGO_INITDB_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.mongodb_secrets.metadata[0].name
                key  = "mongodb-root-password"
              }
            }
          }

          port {
            container_port = 27017
          }

          volume_mount {
            name       = "mongodb-storage"
            mount_path = "/data/db"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "mongodb-storage"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "1Gi"
          }
        }
      }
    }
  }
}

# Secrets for PostgreSQL
resource "kubernetes_secret" "postgres_secrets" {
  metadata {
    name      = "postgres-secrets"
    namespace = kubernetes_namespace.blue.metadata[0].name
  }

  data = {
    "postgres-user"     = base64encode("simaster_user")
    "postgres-password" = base64encode(random_password.postgres_password.result)
  }
}

# Secrets for MongoDB
resource "kubernetes_secret" "mongodb_secrets" {
  metadata {
    name      = "mongodb-secrets"
    namespace = kubernetes_namespace.blue.metadata[0].name
  }

  data = {
    "mongodb-root-username" = base64encode("admin")
    "mongodb-root-password" = base64encode(random_password.mongodb_password.result)
  }
}

# Generate random passwords
resource "random_password" "postgres_password" {
  length  = 16
  special = false
}

resource "random_password" "mongodb_password" {
  length  = 16
  special = false
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

# PostgreSQL Service for Blue namespace
resource "kubernetes_service" "postgres_blue" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.blue.metadata[0].name
  }
  spec {
    selector = {
      app = "postgres"
    }
    port {
      port        = 5432
      target_port = 5432
    }
  }
}

# PostgreSQL Service for Green namespace
resource "kubernetes_service" "postgres_green" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.green.metadata[0].name
  }
  spec {
    selector = {
      app = "postgres"
    }
    port {
      port        = 5432
      target_port = 5432
    }
  }
}

# MongoDB Service for Blue namespace
resource "kubernetes_service" "mongodb_blue" {
  metadata {
    name      = "mongodb"
    namespace = kubernetes_namespace.blue.metadata[0].name
  }
  spec {
    selector = {
      app = "mongodb"
    }
    port {
      port        = 27017
      target_port = 27017
    }
  }
}

# MongoDB Service for Green namespace
resource "kubernetes_service" "mongodb_green" {
  metadata {
    name      = "mongodb"
    namespace = kubernetes_namespace.green.metadata[0].name
  }
  spec {
    selector = {
      app = "mongodb"
    }
    port {
      port        = 27017
      target_port = 27017
    }
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