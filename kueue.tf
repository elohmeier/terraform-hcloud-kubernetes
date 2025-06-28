locals {
  kueue_enabled = var.kueue_enabled

  kueue_values = {
    # Enable Prometheus metrics integration with VictoriaMetrics
    enablePrometheus = var.victoriametrics_enabled

    # # Enable cert-manager integration if available
    # enableCertManager = var.cert_manager_enabled

    # # Enable API Priority and Fairness for better resource management
    # enableVisibilityAPF = true

    controllerManager = {
      replicas = local.control_plane_sum > 1 ? 2 : 1
      # replicas = 1 # no leader election, high cpu usage...
      podDisruptionBudget = {
        enabled = local.control_plane_sum > 1
      }
      topologySpreadConstraints = [
        {
          topologyKey       = "kubernetes.io/hostname"
          maxSkew           = 1
          whenUnsatisfiable = local.control_plane_sum > 2 ? "DoNotSchedule" : "ScheduleAnyway"
          labelSelector = {
            matchLabels = {
              "app.kubernetes.io/instance" = "kueue"
              "app.kubernetes.io/name"     = "kueue"
            }
          }
        }
      ]
      # node tolerations for control-plane only clusters
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
    }
  }
}

resource "kubernetes_namespace_v1" "kueue" {
  count = local.kueue_enabled ? 1 : 0

  metadata {
    name = var.kueue_namespace
  }
}

resource "helm_release" "kueue" {
  count = local.kueue_enabled ? 1 : 0

  name      = "kueue"
  namespace = var.kueue_namespace

  repository       = var.kueue_helm_repository
  chart            = var.kueue_helm_chart
  version          = var.kueue_helm_version
  create_namespace = false
  wait             = false

  values = [
    yamlencode(
      merge(
        local.kueue_values,
        var.kueue_helm_values
      )
    )
  ]

  depends_on = [
    helm_release.cilium,
    kubernetes_namespace_v1.kueue
  ]
}
