variable "cluster_name" {
  description = "Name of the k3d cluster"
  default     = "mini-cluster"
}

variable "k3d_version" {
  description = "Version of k3d to use"
  default     = "v5.8.1"
}

variable "k8s_version" {
  description = "Version of Kubernetes to use"
  default     = "v1.32.0"
}

variable "cert_manager_version" {
  description = "Version of cert-manager to install"
  default     = "v1.8.0"
}

variable "cert_manager_email" {
  description = "Email address for Let's Encrypt notifications"
  type        = string
  default     = "example@gmail.com"
}

variable "environment" {
  description = "Environment (dev or prod)"
  type        = string
  default     = "dev"
}

variable "argocd_version" {
  description = "Version of ArgoCD to install"
  default     = "3.35.4"
}

variable "argocd_ssl_config_url" {
  description = "Secure domain url for the ArgoCD access"
  type        = string
  default     = "https://argocd.example.com"
}

variable "argocd_custom_domain" {
  description = "Custom domain for ArgoCD"
  type        = string
  default     = "argocd.example.com"
}

variable "argocd_custom_tls" {
  description = "Custom custom secret for ArgoCD"
  type        = string
  default     = "argocd-server-tls"
}

variable "argocd_secret_tls" {
  description = "Secret name for ArgoCD to use for TLS"
  type        = string
  default     = "argocd-tls"
}

variable "bind_localhost" {
  description = "Bind the k3d container to host network"
  type        = bool
  default     = true
}

variable "bind_ingress_port" {
  description = "Port to bind the ingress controller to"
  default     = "90"
}

variable "bind_registry_port" {
  description = "Port to bind the container registry to"
  default     = "30000"
}

variable "bind_ports" {
  description = "Additional ports to bind"
  type        = string
  default     = ""
}

variable "docker_io_registry_mirror" {
  description = "Docker.io registry mirror"
  default     = ""
}

variable "host_port_range" {
  description = "Host port range for Kubernetes services"
  default     = "8010-65535"
}

variable "grafana_version" {
  description = "Version of Grafana to install"
  default     = "8.8.4"
}

variable "loki_version" {
  description = "Version of Loki to install"
  default     = "6.24.1"
}

variable "kube_prometheus_stack_version" {
  description = "Version of kube-prometeus-stack controller to install"
  default     = "68.3.3"
}

variable "prometheus_custom_domain" {
  description = "Custom domain for Prometheus server"
  type        = string
  default     = "prometheus.example.com"  # Replace with your actual domain
}

variable "prometheus_port" {
  description = "Port for Prometheus server"
  type        = number
  default     = 9090  # Default Prometheus port, change if needed
}

variable "monitoring_namespace" {
  description = "Namespace for monitoring tools"
  default     = "monitoring"
}

variable "promtail_version" {
  description = "Version of Promtail to install"
  default     = "6.16.5"
}

variable "elasticsearch_version" {
  description = "Version of Elasticsearch to install"
  default     = "7.17.3"
}

variable "kibana_version" {
  description = "Version of Kibana to install"
  default     = "7.17.3"
}

variable "logstash_version" {
  description = "Version of Logstash to install"
  default     = "7.17.3"
}

variable "github_repo_url" {
  description = "GitHub repository URL for monorepo"
  type        = string
  default     = "git@github.com:sample/demo.git"
}
