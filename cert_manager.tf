locals {
  cert_manager_values = {
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
            "app.kubernetes.io/instance"  = "cert-manager"
            "app.kubernetes.io/component" = "controller"
          }
        }
      }
    ],
    nodeSelector = { "node-role.kubernetes.io/control-plane" : "" }
    tolerations = [
      {
        key      = "node-role.kubernetes.io/control-plane"
        effect   = "NoSchedule"
        operator = "Exists"
      }
    ]
  }
}

resource "helm_release" "cert_manager" {
  count = var.cert_manager_enabled ? 1 : 0

  name      = "cert-manager"
  namespace = "cert-manager"

  repository       = var.cert_manager_helm_repository
  chart            = var.cert_manager_helm_chart
  version          = var.cert_manager_helm_version
  create_namespace = true

  set = [
    {
      name  = "crds.enabled"
      value = true
    },
    {
      name  = "startupapicheck.enabled"
      value = false
    }
  ]

  values = [
    yamlencode(
      merge(
        local.cert_manager_values,
        {
          webhook = merge(
            local.cert_manager_values,
            {
              topologySpreadConstraints = [
                {
                  topologyKey       = local.cert_manager_values.topologySpreadConstraints[0].topologyKey
                  maxSkew           = local.cert_manager_values.topologySpreadConstraints[0].maxSkew
                  whenUnsatisfiable = local.cert_manager_values.topologySpreadConstraints[0].whenUnsatisfiable
                  labelSelector = {
                    matchLabels = {
                      "app.kubernetes.io/instance"  = "cert-manager"
                      "app.kubernetes.io/component" = "webhook"
                    }
                  }
                }
              ]
            }
          ),
          cainjector = merge(
            local.cert_manager_values,
            {
              topologySpreadConstraints = [
                {
                  topologyKey       = local.cert_manager_values.topologySpreadConstraints[0].topologyKey
                  maxSkew           = local.cert_manager_values.topologySpreadConstraints[0].maxSkew
                  whenUnsatisfiable = local.cert_manager_values.topologySpreadConstraints[0].whenUnsatisfiable
                  labelSelector = {
                    matchLabels = {
                      "app.kubernetes.io/instance"  = "cert-manager"
                      "app.kubernetes.io/component" = "cainjector"
                    }
                  }
                }
              ]
            }
          )
        }
      )
    ),
    yamlencode(var.cert_manager_helm_values)
  ]

  depends_on = [helm_release.cilium]
}
