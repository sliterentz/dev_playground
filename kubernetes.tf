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
      test = "sample"
    }
    namespace = "dev-playground"
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        test = "sample"
      }
    }

    template {
      metadata {
        labels = {
          test = "sample"
        }
      }

      spec {
        container {
          image = "sample-api:1.0.0"
          name  = "sample"

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

# MinIO StatefulSet
resource "kubernetes_stateful_set" "minio" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace.blue.metadata[0].name
  }

  spec {
    service_name = "minio"
    replicas     = 1

    selector {
      match_labels = {
        app = "minio"
      }
    }

    template {
      metadata {
        labels = {
          app = "minio"
        }
      }

      spec {
        container {
          name  = "minio"
          image = "minio/minio:RELEASE.2023-05-27T05-56-19Z"
          args  = ["server", "/data"]

          env {
            name = "MINIO_ACCESS_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.minio_secrets.metadata[0].name
                key  = "minio-access-key"
              }
            }
          }
          env {
            name = "MINIO_SECRET_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.minio_secrets.metadata[0].name
                key  = "minio-secret-key"
              }
            }
          }

          port {
            container_port = 9000
          }

          volume_mount {
            name       = "minio-storage"
            mount_path = "/data"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "minio-storage"
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

# Secrets for MinIO
resource "kubernetes_secret" "minio_secrets" {
  metadata {
    name      = "minio-secrets"
    namespace = kubernetes_namespace.blue.metadata[0].name
  }

  data = {
    "minio-access-key" = base64encode(random_string.minio_access_key.result)
    "minio-secret-key" = base64encode(random_password.minio_secret_key.result)
  }
}

# MinIO Service for Blue namespace
resource "kubernetes_service" "minio_blue" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace.blue.metadata[0].name
  }
  spec {
    selector = {
      app = "minio"
    }
    port {
      port        = 9000
      target_port = 9000
    }
  }
}

# MinIO Service for Green namespace
resource "kubernetes_service" "minio_green" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace.green.metadata[0].name
  }
  spec {
    selector = {
      app = "minio"
    }
    port {
      port        = 9000
      target_port = 9000
    }
  }
}

# Generate random access key and secret key for MinIO
resource "random_string" "minio_access_key" {
  length  = 20
  special = false
}

resource "random_password" "minio_secret_key" {
  length  = 40
  special = false
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
          env {
            name  = "POSTGRES_DB"
            value = "sample_db"
          }
          # Add this new volume mount for initialization scripts
          volume_mount {
            name       = "init-script"
            mount_path = "/docker-entrypoint-initdb.d"
            read_only  = true
          }
          port {
            container_port = 5432
          }
          volume_mount {
            name       = "postgres-storage"
            mount_path = "/var/lib/postgresql/data"
            sub_path   = "postgres"
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 6
          }

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres"]
            }
            initial_delay_seconds = 15
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 6
          }
        }
        # Add this new volume for initialization scripts
        volume {
          name = "init-script"
          config_map {
            name = kubernetes_config_map.postgres_init_script.metadata[0].name
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

    update_strategy {
      type = "RollingUpdate"
      rolling_update {
        partition = 0
      }
    }
  }
}

# Generate random password for app_user
resource "random_password" "app_user_password" {
  length  = 16
  special = false
}

# New ConfigMap for PostgreSQL initialization script
resource "kubernetes_config_map" "postgres_init_script" {
  metadata {
    name      = "postgres-init-script"
    namespace = kubernetes_namespace.blue.metadata[0].name
  }

  data = {
    "init.sql" = <<-EOT
      CREATE ROLE sample_user WITH LOGIN PASSWORD '${random_password.app_user_password.result}';
      CREATE DATABASE sample_db;
      GRANT ALL PRIVILEGES ON DATABASE sample_db TO sample_user;
      ALTER ROLE sample_user CREATEDB;
    EOT
  }
}

# Add app_user credentials to the existing PostgreSQL secrets
resource "kubernetes_secret" "postgres_secrets" {
  metadata {
    name      = "postgres-secrets"
    namespace = kubernetes_namespace.blue.metadata[0].name
  }

  data = {
    "postgres-user"     = "postgres"
    "postgres-password" = base64encode(random_password.postgres_password.result)
    "app-user"          = "sample_user"
    "app-user-password" = base64encode(random_password.app_user_password.result)
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
      app = "sample-app"
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