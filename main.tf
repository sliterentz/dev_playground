terraform {
required_version = ">=0.13.1"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.1.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.19.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.3.0"
    }
  }
}

locals {
  acme_server = var.environment == "prod" ? "https://acme-v02.api.letsencrypt.org/directory" : "https://acme-staging-v02.api.letsencrypt.org/directory"
}

provider "kubectl" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].labels,
      metadata[0].annotations,
    ]
  }
}

resource "kubectl_manifest" "ingress_nginx" {
  count     = var.bind_ingress_port != "-" ? 1 : 0
  yaml_body = templatefile("${path.module}/manifests/ingress-nginx.yaml", {
    environment = var.environment
    argocd_server_domain = var.argocd_custom_domain
    argocd_server_tls = var.argocd_custom_tls
  })

  depends_on = [kubernetes_namespace.argocd]

  wait = true
  server_side_apply = true

  timeouts {
    create = "2m"
  }
}

resource "kubectl_manifest" "registry" {
  count     = var.bind_registry_port != "0" ? 1 : 0
  yaml_body = file("${path.module}/manifests/registry.yaml")

  wait = true
  server_side_apply = true

  timeouts {
    create = "2m"
  }
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_version
  namespace  = "cert-manager"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [kubernetes_namespace.argocd]
}

resource "kubectl_manifest" "cluster_issuer" {
  yaml_body = templatefile("${path.module}/manifests/cluster-issuer.yaml", {
    environment = var.environment
    acme_server = local.acme_server
    email       = var.cert_manager_email
  })

  depends_on = [helm_release.cert_manager]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  create_namespace = false  # We're creating the namespace separately

  values = [
    templatefile("${path.module}/values/argocd-values.yaml", {
      environment = var.environment
      argocd_config_url = var.argocd_ssl_config_url
      argocd_server_domain = var.argocd_custom_domain
      argocd_secret_tls = var.argocd_secret_tls
    })
  ]

  set {
    name  = "server.ingress.enabled"
    value = "true"
  }

  set {
    name  = "server.ingress.annotations.kubernetes\\.io/ingress\\.class"
    value = "nginx"
  }

  set {
    name  = "server.ingress.annotations.cert-manager\\.io/cluster-issuer"
    value = "letsencrypt-${var.environment}"  # Make sure this matches your cluster issuer name
  }

  set {
    name  = "server.ingress.annotations.nginx\\.ingress\\.kubernetes\\.io/ssl-passthrough"
    value = "true"
  }

  set {
    name  = "server.ingress.annotations.nginx\\.ingress\\.kubernetes\\.io/backend-protocol"
    value = "HTTPS"
  }

  set {
    name  = "server.ingress.annotations.nginx\\.ingress\\.kubernetes\\.io/force-ssl-redirect"
    value = "true"
  }

  set {
    name  = "server.ingress.annotations.nginx\\.ingress\\.kubernetes\\.io/auth-tls-verify-client"
    value = "off"
  }

  set {
    name  = "server.ingress.tls[0].hosts[0]"
    value = var.argocd_custom_domain  # Replace with your actual domain
  }

  set {
    name  = "server.ingress.tls[0].secretName"
    value = var.argocd_custom_tls
  }

  set {
    name  = "server.ingress.hosts[0]"
    value = var.argocd_custom_domain  # Replace with your actual domain
  }

  depends_on = [kubernetes_namespace.argocd, kubectl_manifest.cluster_issuer]
}

resource "kubectl_manifest" "argocd_servicemonitor" {
  yaml_body = <<-YAML
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-server
  namespace: ${kubernetes_namespace.monitoring.metadata[0].name}
  labels:
    release: prometheus-operator
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-server
  namespaceSelector:
    matchNames:
      - argocd
  endpoints:
    - port: http
      path: /metrics
  YAML

  depends_on = [helm_release.prometheus_operator, helm_release.argocd]
}

resource "kubectl_manifest" "dev_app_servicemonitor" {
  yaml_body = <<-YAML
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: dev-app-monitor
  namespace: ${kubernetes_namespace.monitoring.metadata[0].name}
  labels:
    release: prometheus-operator
spec:
  selector:
    matchLabels:
      app: dev-app
  namespaceSelector:
    matchNames:
      - dev-app
  endpoints:
    - port: http
      path: /metrics
  YAML

  depends_on = [helm_release.prometheus_operator]
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.monitoring_namespace
  }

  lifecycle {
    ignore_changes = [
      metadata[0].labels,
      metadata[0].annotations,
    ]
  }
}

resource "helm_release" "prometheus_operator" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  set {
    name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  set {
    name  = "prometheus.prometheusSpec.serviceMonitorSelector.matchLabels.release"
    value = "kube-prometheus-stack"
  }

  set {
    name  = "prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  set {
    name  = "prometheus.prometheusSpec.podMonitorSelector.matchLabels.release"
    value = "kube-prometheus-stack"
  }

  set {
    name  = "prometheus-node-exporter.service.port"
    value = "30206"
  }

  set {
    name  = "prometheus-node-exporter.hostNetwork"
    value = "false"
  }

  set {
    name  = "prometheus.prometheusSpec.configReloaderCpu"
    value = "100m"
  }

  set {
    name  = "prometheus.prometheusSpec.configReloaderMemory"
    value = "50Mi"
  }

  set {
    name  = "grafana.enabled"
    value = "true"
  }

  set {
    name  = "grafana.adminPassword"
    value = "prom-operator"
  }

  values = [
    <<-EOT
    prometheus:
      prometheusSpec:
        ruleSelector: {}
        ruleNamespaceSelector: {}
        ruleSelectorNilUsesHelmValues: false
        serviceMonitorSelector: {}
        serviceMonitorNamespaceSelector: {}
        podMonitorSelector: {}
        podMonitorNamespaceSelector: {}
        storageSpec:
          volumeClaimTemplate:
            spec:
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 10Gi
        additionalScrapeConfigs:
          - job_name: 'argocd-metrics'
            kubernetes_sd_configs:
              - role: endpoints
                namespaces:
                  names: ['argocd']
          - job_name: 'dev-app-metrics'
            kubernetes_sd_configs:
              - role: endpoints
                namespaces:
                  names: ['dev-app']
    additionalPrometheusRulesMap:
      rule-name:
        groups:
          - name: argocd
            rules:
              - alert: ArgoCD Server Down
                expr: absent(up{job="argocd-server"})
                for: 5m
                labels:
                  severity: critical
                annotations:
                  summary: "ArgoCD Server is down"
                  description: "ArgoCD Server has been down for more than 5 minutes."
    grafana:
      enabled: true
      adminPassword: prom-operator
    EOT
  ]

  depends_on = [kubernetes_namespace.monitoring]
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = var.grafana_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  set {
    name  = "persistence.enabled"
    value = "false"
  }
  
  set {
    name  = "rbac.pspEnabled"
    value = "false"
  }

  set {
    name  = "securityContext.runAsUser"
    value = "1000"
  }

  set {
    name  = "securityContext.runAsGroup"
    value = "1000"
  }

  set {
    name  = "securityContext.fsGroup"
    value = "1000"
  }

  set {
    name  = "podSecurityContext.runAsUser"
    value = "1000"
  }

  set {
    name  = "podSecurityContext.runAsGroup"
    value = "1000"
  }

  set {
    name  = "podSecurityContext.fsGroup"
    value = "1000"
  }

  set {
    name  = "datasources.datasources\\.yaml.apiVersion"
    value = "1"
  }

  set {
    name  = "datasources.datasources\\.yaml.datasources[0].name"
    value = "Prometheus"
  }

  set {
    name  = "datasources.datasources\\.yaml.datasources[0].type"
    value = "prometheus"
  }

  set {
    name  = "datasources.datasources\\.yaml.datasources[0].url"
    value = "http://${var.prometheus_custom_domain}:${var.prometheus_port}"
  }

  set {
    name  = "datasources.datasources\\.yaml.datasources[0].jsonData.timeInterval"
    value = "15s"
  }

  set {
    name  = "datasources.datasources\\.yaml.datasources[0].access"
    value = "proxy"
  }

  set {
    name  = "datasources.datasources\\.yaml.datasources[0].isDefault"
    value = "true"
  }

  set {
    name  = "datasources.datasources\\.yaml.datasources[1].name"
    value = "Loki"
  }

  set {
    name  = "datasources.datasources\\.yaml.datasources[1].type"
    value = "loki"
  }

  set {
    name  = "datasources.datasources\\.yaml.datasources[1].url"
    value = "http://loki.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3100"
  }

  set {
    name  = "datasources.datasources\\.yaml.datasources[1].access"
    value = "proxy"
  }
}

resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  set {
    name  = "persistence.enabled"
    value = "false"
  }

  set {
    name  = "loki.auth_enabled"
    value = "false"
  }

  set {
    name  = "promtail.enabled"
    value = "true"
  }

  set {
    name  = "podSecurityPolicy.enabled"
    value = "false"
  }

  set {
    name  = "rbac.pspEnabled"
    value = "false"
  }

  set {
    name  = "loki.podSecurityContext.enabled"
    value = "false"
  }

  set {
    name  = "loki.containerSecurityContext.enabled"
    value = "false"
  }
}

resource "helm_release" "promtail" {
  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = var.promtail_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  
  values = [
    <<-EOT
    config:
      lokiAddress: http://loki.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3100/loki/api/v1/push
      snippets:
        extraScrapeConfigs: |
          - job_name: kubernetes-pods-name
            pipeline_stages:
              - docker: {}
            kubernetes_sd_configs:
            - role: pod
            relabel_configs:
            - source_labels:
              - __meta_kubernetes_pod_label_name
              target_label: __service__
            - source_labels:
              - __meta_kubernetes_pod_node_name
              target_label: __host__
            - action: labelmap
              regex: __meta_kubernetes_pod_label_(.+)
            - action: replace
              replacement: $1
              separator: /
              source_labels:
              - __meta_kubernetes_namespace
              - __service__
              target_label: job
            - action: replace
              source_labels:
              - __meta_kubernetes_namespace
              target_label: namespace
            - action: replace
              source_labels:
              - __meta_kubernetes_pod_name
              target_label: pod
            - action: replace
              source_labels:
              - __meta_kubernetes_pod_container_name
              target_label: container
            - replacement: /var/log/pods/*$1/*.log
              separator: /
              source_labels:
              - __meta_kubernetes_pod_uid
              - __meta_kubernetes_pod_container_name
              target_label: __path__
          - job_name: argocd-server-logs
            static_configs:
            - targets:
                - localhost
              labels:
                job: argocd-server
                __path__: /var/log/containers/argocd-server*.log

    rbac:
      create: true
      pspEnabled: false

    serviceAccount:
      create: true
      name: promtail

    tolerations:
    - effect: NoSchedule
      operator: Exists

    EOT
  ]

  set {
    name  = "rbac.create"
    value = "true"
  }

  set {
    name  = "rbac.pspEnabled"
    value = "false"
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "promtail"
  }

  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }

  set {
    name  = "tolerations[0].operator"
    value = "Exists"
  }
}

resource "helm_release" "elasticsearch" {
  name       = "elasticsearch"
  repository = "https://helm.elastic.co"
  chart      = "elasticsearch"
  version    = var.elasticsearch_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  timeout = 900 # 15 minutes

  set {
    name  = "persistence.enabled"
    value = "false"
  }

  # Add resource limits to speed up deployment
  set {
    name  = "esJavaOpts"
    value = "-Xmx512m -Xms512m"
  }

  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "512Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "1000m"
  }

  set {
    name  = "resources.limits.memory"
    value = "1Gi"
  }

  # Reduce the number of replicas for faster deployment
  set {
    name  = "replicas"
    value = "1"
  }

  # Disable security features for faster deployment (only for testing)
  set {
    name  = "antiAffinity"
    value = "soft"
  }

  set {
    name  = "minimumMasterNodes"
    value = "1"
  }
}

resource "helm_release" "kibana" {
  name       = "kibana"
  repository = "https://helm.elastic.co"
  chart      = "kibana"
  version    = var.kibana_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  set {
    name  = "elasticsearch.hosts"
    value = "${helm_release.elasticsearch.name}-master:9200"
  }
}

resource "helm_release" "logstash" {
  name       = "logstash"
  repository = "https://helm.elastic.co"
  chart      = "logstash"
  version    = var.logstash_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  timeout = 900 # 15 minutes

  set {
    name  = "elasticsearch.hosts"
    value = "${helm_release.elasticsearch.name}-master:9200"
  }

  # Reduce resource requests and limits
  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "512Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "resources.limits.memory"
    value = "1Gi"
  }

  # Reduce the number of replicas
  set {
    name  = "replicaCount"
    value = "1"
  }

  # Disable persistence for faster deployment (only for testing)
  set {
    name  = "persistence.enabled"
    value = "false"
  }

  # Adjust Java options
  set {
    name  = "logstashJavaOpts"
    value = "-Xmx512m -Xms256m"
  }

  depends_on = [helm_release.elasticsearch]
}
