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

resource "kubernetes_secret" "grafana_admin_credentials" {
  metadata {
    name      = "grafana-admin-credentials"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    admin-user     = "admin"
    admin-password = var.grafana_admin_password
  }

  type = "Opaque"
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

  # Add these new configurations
  set {
    name  = "prometheus.service.type"
    value = "ClusterIP"
  }

  set {
    name  = "prometheus.service.port"
    value = "9090"
  }

  set {
    name  = "prometheus.prometheusSpec.externalUrl"
    value = "http://kube-prometheus-stack-prometheus.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:${var.prometheus_port}"
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
          - job_name: 'sample-blue-metrics'
            kubernetes_sd_configs:
              - role: endpoints
                namespaces:
                  names: ['sample-blue']
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
        additionalLabels: {}
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
    value = "http://kube-prometheus-stack-prometheus.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:${var.prometheus_port}"
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

  timeout = 900 # Increase timeout to 15 minutes (900 seconds)

  values = [
    <<-EOT
    loki:
      auth_enabled: false
      commonConfig:
        replication_factor: 1
      storage:
        type: filesystem
      schemaConfig:
        configs:
          - from: 2020-10-24
            store: tsdb
            object_store: filesystem
            schema: v13
            index:
              prefix: index_
              period: 24h
    
    singleBinary:
      replicas: 1
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 200m
          memory: 256Mi
    
    persistence:
      enabled: true
      size: 5Gi
      storageClassName: standard
    
    serviceMonitor:
      enabled: true
    
    monitoring:
      selfMonitoring:
        enabled: false
        grafanaAgent:
          installOperator: false
    
    test:
      enabled: false

    # Set deployment mode to singleBinary
    deploymentMode: "SingleBinary<->SimpleScalable"

    # Disable other deployment modes
    backend:
      enabled: false
    read:
      enabled: false
    write:
      enabled: false

    limits_config:
      enforce_metric_name: false
      reject_old_samples: true
      reject_old_samples_max_age: 168h
      max_cache_freshness_per_query: 10m
      split_queries_by_interval: 15m
      allow_structured_metadata: true
    chunk_store_config:
      max_look_back_period: 0s
    table_manager:
      retention_deletes_enabled: false
      retention_period: 0s
    compactor:
      working_directory: /data/loki/compactor
      shared_store: filesystem

    gateway:
      enabled: true
      ingress:
        enabled: false
      service:
        type: ClusterIP
    EOT
  ]

  set {
    name  = "persistence.enabled"
    value = "true"
  }

  set {
    name  = "persistence.size"
    value = "5Gi"
  }

  set {
    name  = "persistence.storageClassName"
    value = "standard"
  }

  set {
    name  = "loki.auth_enabled"
    value = "false"
  }

  set {
    name  = "loki.commonConfig.replication_factor"
    value = "1"
  }

  set {
    name  = "singleBinary.replicas"
    value = "1"
  }

  depends_on = [kubernetes_namespace.monitoring]
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

    resources:
      limits:
        cpu: 200m
        memory: 128Mi
      requests:
        cpu: 100m
        memory: 128Mi
    EOT
  ]

  set {
    name  = "config.lokiAddress"
    value = "http://loki.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3100/loki/api/v1/push"
  }

  depends_on = [helm_release.loki]
}