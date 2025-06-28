locals {
  kyverno_enabled = var.kyverno_enabled

  kyverno_node_placement = {
    nodeSelector = local.worker_sum == 0 ? {
      "node-role.kubernetes.io/control-plane" = ""
    } : {}
    tolerations = local.worker_sum == 0 ? [
      {
        key      = "node-role.kubernetes.io/control-plane"
        operator = "Exists"
        effect   = "NoSchedule"
      }
    ] : []
  }

  kyverno_service_monitor = {
    serviceMonitor = {
      enabled = var.victoriametrics_enabled
    }
  }

  kyverno_values = {
    admissionController = merge(
      local.kyverno_node_placement,
      local.kyverno_service_monitor,
    )
    backgroundController = merge(
      local.kyverno_node_placement,
      local.kyverno_service_monitor,
    )
    cleanupController = merge(
      local.kyverno_node_placement,
      local.kyverno_service_monitor,
    )
    reportsController = merge(
      local.kyverno_node_placement,
      local.kyverno_service_monitor,
    )
    grafana = {
      enabled   = var.victoriametrics_enabled
      namespace = "victoriametrics"
    }
  }
}

resource "kubernetes_namespace_v1" "kyverno" {
  count = local.kyverno_enabled ? 1 : 0

  metadata {
    name = "kyverno"
  }
}

resource "helm_release" "kyverno" {
  count = local.kyverno_enabled ? 1 : 0

  name      = "kyverno"
  namespace = "kyverno"

  repository       = var.kyverno_helm_repository
  chart            = var.kyverno_helm_chart
  version          = var.kyverno_helm_version
  create_namespace = false
  wait             = false

  values = [
    yamlencode(
      merge(
        local.kyverno_values,
        var.kyverno_helm_values
      )
    )
  ]

  depends_on = [
    helm_release.cilium,
    kubernetes_namespace_v1.kyverno,
  ]
}
