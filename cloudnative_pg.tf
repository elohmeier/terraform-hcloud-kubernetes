locals {
  cloudnative_pg_values = {
    replicaCount = local.control_plane_sum > 1 ? 2 : 1
    podDisruptionBudget = {
      enabled      = local.control_plane_sum > 1
      minAvailable = local.control_plane_sum > 1 ? 1 : 0
    }
    topologySpreadConstraints = [
      {
        topologyKey       = "kubernetes.io/hostname"
        maxSkew           = 1
        whenUnsatisfiable = local.control_plane_sum > 2 ? "DoNotSchedule" : "ScheduleAnyway"
        labelSelector = {
          matchLabels = {
            "app.kubernetes.io/instance" = "cloudnative-pg"
            "app.kubernetes.io/name"     = "cloudnative-pg"
          }
        }
      }
    ]
    nodeSelector = { "node-role.kubernetes.io/control-plane" : "" }
    tolerations = [
      {
        key      = "node-role.kubernetes.io/control-plane"
        effect   = "NoSchedule"
        operator = "Exists"
      }
    ]
    monitoring = {
      podMonitorEnabled = var.prometheus_operator_crds_enabled
    }
  }
}

resource "helm_release" "cloudnative_pg" {
  count = var.cloudnative_pg_enabled ? 1 : 0

  name      = "cnpg"
  namespace = "cnpg-system"

  repository       = var.cloudnative_pg_helm_repository
  chart            = var.cloudnative_pg_helm_chart
  version          = var.cloudnative_pg_helm_version
  create_namespace = true

  values = [
    yamlencode(
      merge(
        local.cloudnative_pg_values,
        var.cloudnative_pg_helm_values
      )
    )
  ]

  depends_on = [helm_release.cilium]
}

resource "helm_release" "cloudnative_pg_grafana_dashboard" {
  count = var.cloudnative_pg_enabled && var.victoriametrics_enabled ? 1 : 0

  name      = "cnpg-grafana-dashboard"
  namespace = "victoriametrics"

  repository       = var.cloudnative_pg_grafana_dashboard_helm_repository
  chart            = var.cloudnative_pg_grafana_dashboard_helm_chart
  version          = var.cloudnative_pg_grafana_dashboard_helm_version
  create_namespace = false

  values = [
    yamlencode(
      merge(
        {
          grafanaDashboard = {
            namespace = "victoriametrics"
            labels = {
              grafana_dashboard = "1"
            }
          }
        },
        var.cloudnative_pg_grafana_dashboard_helm_values
      )
    )
  ]

  depends_on = [
    helm_release.cloudnative_pg,
    helm_release.victoriametrics
  ]
}
