locals {
  argocd_enabled                   = var.argocd_enabled
  argocd_tailscale_ingress_enabled = var.argocd_enabled && var.tailscale_enabled && var.argocd_tailscale_ingress_enabled
  argocd_tailscale_hostname        = coalesce(var.argocd_tailscale_hostname, "${var.cluster_name}-argocd")

  argocd_values = {
    # node tolerations for control-plane only clusters
    controller = merge(
      {
        tolerations = local.worker_sum == 0 ? [
          {
            key      = "node-role.kubernetes.io/control-plane"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        ] : []
        nodeSelector = local.worker_sum == 0 ? {
          "node-role.kubernetes.io/control-plane" = ""
        } : {}
      },
      var.prometheus_operator_crds_enabled ? {
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = true
          }
        }
      } : {}
    )
    server = merge(
      {
        ingress = {
          enabled = false
        }
        tolerations = local.worker_sum == 0 ? [
          {
            key      = "node-role.kubernetes.io/control-plane"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        ] : []
        nodeSelector = local.worker_sum == 0 ? {
          "node-role.kubernetes.io/control-plane" = ""
        } : {}
      },
      var.prometheus_operator_crds_enabled ? {
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = true
          }
        }
      } : {}
    )
    repoServer = merge(
      {
        tolerations = local.worker_sum == 0 ? [
          {
            key      = "node-role.kubernetes.io/control-plane"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        ] : []
        nodeSelector = local.worker_sum == 0 ? {
          "node-role.kubernetes.io/control-plane" = ""
        } : {}
      },
      var.prometheus_operator_crds_enabled ? {
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = true
          }
        }
      } : {}
    )
    applicationSet = merge(
      {
        tolerations = local.worker_sum == 0 ? [
          {
            key      = "node-role.kubernetes.io/control-plane"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        ] : []
        nodeSelector = local.worker_sum == 0 ? {
          "node-role.kubernetes.io/control-plane" = ""
        } : {}
      },
      var.prometheus_operator_crds_enabled ? {
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = true
          }
        }
      } : {}
    )
    configs = {
      params = {
        "server.insecure" = local.argocd_tailscale_ingress_enabled
      }
    }
  }
}

resource "kubernetes_namespace_v1" "argocd" {
  count = local.argocd_enabled ? 1 : 0

  metadata {
    name = var.argocd_namespace
  }
}

resource "helm_release" "argocd" {
  count = local.argocd_enabled ? 1 : 0

  name      = "argocd"
  namespace = var.argocd_namespace

  repository       = var.argocd_helm_repository
  chart            = var.argocd_helm_chart
  version          = var.argocd_helm_version
  create_namespace = false
  wait             = false

  values = [
    yamlencode(
      merge(
        local.argocd_values,
        var.argocd_helm_values
      )
    )
  ]

  depends_on = [
    helm_release.cilium,
    kubernetes_namespace_v1.argocd
  ]
}

resource "kubernetes_ingress_v1" "argocd_tailscale" {
  count = local.argocd_tailscale_ingress_enabled ? 1 : 0

  metadata {
    name      = "argocd-tailscale"
    namespace = var.argocd_namespace
  }

  spec {
    ingress_class_name = "tailscale"

    rule {
      host = "${local.argocd_tailscale_hostname}.${var.tailscale_tailnet}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port {
                name = "http"
              }
            }
          }
        }
      }
    }

    tls {
      hosts = ["${local.argocd_tailscale_hostname}.${var.tailscale_tailnet}"]
    }
  }

  depends_on = [
    helm_release.argocd
  ]
}

data "http" "argocd_grafana_dashboard" {
  count = local.argocd_enabled && var.victoriametrics_enabled && var.prometheus_operator_crds_enabled ? 1 : 0

  url = "https://raw.githubusercontent.com/argoproj/argo-cd/refs/heads/master/examples/dashboard.json"
}

resource "kubernetes_config_map_v1" "argocd_grafana_dashboard" {
  count = local.argocd_enabled && var.victoriametrics_enabled && var.prometheus_operator_crds_enabled ? 1 : 0

  metadata {
    name      = "argocd-grafana-dashboard"
    namespace = "victoriametrics"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "argocd-dashboard.json" = data.http.argocd_grafana_dashboard[0].response_body
  }

  depends_on = [
    helm_release.argocd
  ]
}
