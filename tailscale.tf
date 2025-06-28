resource "helm_release" "tailscale" {
  count = var.tailscale_enabled ? 1 : 0

  name      = "tailscale-operator"
  namespace = "tailscale"

  repository       = var.tailscale_helm_repository
  chart            = var.tailscale_helm_chart
  version          = var.tailscale_helm_version
  create_namespace = true

  set = [
    {
      name  = "oauth.clientId"
      value = var.tailscale_oauth_client_id
    },
    {
      name  = "oauth.clientSecret"
      value = var.tailscale_oauth_client_secret
    }
  ]

  values = [
    yamlencode({
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
              "app.kubernetes.io/instance" = "tailscale-operator"
              "app.kubernetes.io/name"     = "tailscale-operator"
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
    }),
    yamlencode(var.tailscale_helm_values)
  ]

  depends_on = [helm_release.cilium]
}
