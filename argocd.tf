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

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  create_namespace = false

  values = [
    templatefile("${path.module}/values/argocd-values.yaml", {
      environment          = var.environment
      argocd_config_url    = var.argocd_ssl_config_url
      argocd_server_domain = var.argocd_custom_domain
      argocd_secret_tls    = var.argocd_secret_tls
      github_repo_url      = var.github_repo_url
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

  depends_on = [kubernetes_namespace.argocd, kubectl_manifest.cluster_issuer]
}

resource "kubernetes_secret" "argocd_github_ssh" {
  metadata {
    name      = "argocd-github-ssh"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  type = "Opaque"

  data = {
    "name"          = "sample_app"
    "sshPrivateKey" = var.github_ssh_private_key
    "url"           = var.github_repo_url
    "type"          = "git"
    "insecure"      = "true"
    "enableLfs"     = "true"
  }

  depends_on = [helm_release.argocd]
}

# ArgoCD Application for blue-green deployment
resource "kubectl_manifest" "sample_app" {
  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample_app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${var.github_repo_url}
    targetRevision: develop
    path: development
  destination:
    server: https://kubernetes.default.svc
    namespace: blue
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/template/spec/containers/0/image
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/template/spec/containers/0/imagePullPolicy
YAML

  depends_on = [helm_release.argocd, kubernetes_secret.argocd_github_ssh]
}
