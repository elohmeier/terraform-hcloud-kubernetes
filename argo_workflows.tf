locals {
  argo_workflows_enabled                   = var.argo_workflows_enabled
  argo_workflows_tailscale_ingress_enabled = var.argo_workflows_enabled && var.tailscale_enabled && var.argo_workflows_tailscale_ingress_enabled
  argo_workflows_tailscale_hostname        = coalesce(var.argo_workflows_tailscale_hostname, "${var.cluster_name}-argo-workflows")
  argo_workflows_artifact_s3_location      = coalesce(var.s3_location, local.control_plane_nodepools[0].location)
  argo_workflows_artifact_s3_region        = local.location_to_zone[local.argo_workflows_artifact_s3_location]
  argo_workflows_artifact_s3_endpoint      = "${local.argo_workflows_artifact_s3_location}.your-objectstorage.com"

  # Use auto-created bucket name for Argo Workflows if bucket is not explicitly provided
  argo_workflows_artifact_s3_bucket_name = var.argo_workflows_artifact_s3_bucket != null ? var.argo_workflows_artifact_s3_bucket : (
    var.argo_workflows_enabled && var.argo_workflows_artifact_s3_enabled ? "${var.cluster_name}-argo-workflows-artifacts" : null
  )

  # Calculate total node count for HA decisions
  argo_workflows_total_nodes = local.worker_sum > 0 ? local.worker_sum : local.control_plane_sum
  argo_workflows_ha_enabled  = local.argo_workflows_total_nodes > 1

  # Node placement configuration
  argo_workflows_node_placement = {
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

  # HA configuration for server
  argo_workflows_server_ha = {
    autoscaling = {
      enabled     = local.argo_workflows_ha_enabled
      minReplicas = 2
    }
    pdb = {
      enabled      = local.argo_workflows_ha_enabled
      minAvailable = 1
    }
  }

  # HA configuration for controller
  argo_workflows_controller_ha = {
    replicas = local.argo_workflows_ha_enabled ? 2 : 1
    pdb = {
      enabled      = local.argo_workflows_ha_enabled
      minAvailable = 1
    }
  }

  # Monitoring configuration
  argo_workflows_monitoring = {
    metricsConfig = {
      enabled = var.prometheus_operator_crds_enabled
    }
    # telemetryConfig = {
    #   enabled = var.prometheus_operator_crds_enabled
    # }
    serviceMonitor = {
      enabled = var.prometheus_operator_crds_enabled
    }
  }

  argo_workflows_values = {
    server = merge(
      {
        enabled = true
        ingress = {
          enabled = false
        }
      },
      local.argo_workflows_node_placement,
      local.argo_workflows_server_ha
    )
    controller = merge(
      {
        workflowNamespaces = var.argo_workflows_managed_namespaces
      },
      local.argo_workflows_node_placement,
      local.argo_workflows_monitoring,
      local.argo_workflows_controller_ha
    )
    artifactRepository = var.argo_workflows_artifact_s3_enabled ? {
      s3 = {
        bucket   = local.argo_workflows_artifact_s3_bucket_name
        endpoint = local.argo_workflows_artifact_s3_endpoint
        region   = local.argo_workflows_artifact_s3_region
        insecure = false
        accessKeySecret = {
          name = "argo-workflows-s3-creds"
          key  = "accessKey"
        }
        secretKeySecret = {
          name = "argo-workflows-s3-creds"
          key  = "secretKey"
        }
      }
    } : {}
  }
}

resource "kubernetes_namespace_v1" "argo_workflows" {
  count = local.argo_workflows_enabled ? 1 : 0

  metadata {
    name = var.argo_workflows_namespace
  }
}

resource "kubernetes_namespace_v1" "argo_workflows_managed" {
  for_each = local.argo_workflows_enabled ? toset(var.argo_workflows_managed_namespaces) : toset([])

  metadata {
    name = each.key
  }
}

resource "kubernetes_secret_v1" "argo_workflows_s3_creds" {
  count = local.argo_workflows_enabled && var.argo_workflows_artifact_s3_enabled ? 1 : 0

  metadata {
    name      = "argo-workflows-s3-creds"
    namespace = var.argo_workflows_namespace
  }

  data = {
    accessKey = var.s3_admin_access_key
    secretKey = var.s3_admin_secret_key
  }

  depends_on = [
    kubernetes_namespace_v1.argo_workflows
  ]
}

resource "helm_release" "argo_workflows" {
  count = local.argo_workflows_enabled ? 1 : 0

  name      = "argo-workflows"
  namespace = var.argo_workflows_namespace

  repository       = var.argo_workflows_helm_repository
  chart            = var.argo_workflows_helm_chart
  version          = var.argo_workflows_helm_version
  create_namespace = false
  wait             = false

  values = [
    yamlencode(
      merge(
        local.argo_workflows_values,
        var.argo_workflows_helm_values
      )
    )
  ]

  depends_on = [
    helm_release.cilium,
    kubernetes_namespace_v1.argo_workflows,
    kubernetes_namespace_v1.argo_workflows_managed,
    kubernetes_secret_v1.argo_workflows_s3_creds
  ]
}

resource "kubernetes_ingress_v1" "argo_workflows_tailscale" {
  count = local.argo_workflows_tailscale_ingress_enabled ? 1 : 0

  metadata {
    name      = "argo-workflows-tailscale"
    namespace = var.argo_workflows_namespace
  }

  spec {
    ingress_class_name = "tailscale"

    rule {
      host = "${local.argo_workflows_tailscale_hostname}.${var.tailscale_tailnet}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argo-workflows-server"
              port {
                number = 2746
              }
            }
          }
        }
      }
    }

    tls {
      hosts = ["${local.argo_workflows_tailscale_hostname}.${var.tailscale_tailnet}"]
    }
  }

  depends_on = [
    helm_release.argo_workflows
  ]
}

data "http" "argo_workflows_grafana_dashboard" {
  count = local.argo_workflows_enabled && var.victoriametrics_enabled && var.prometheus_operator_crds_enabled ? 1 : 0

  url = "https://raw.githubusercontent.com/argoproj/argo-workflows/refs/heads/main/examples/grafana-dashboard.json"
}

resource "kubernetes_config_map_v1" "argo_workflows_grafana_dashboard" {
  count = local.argo_workflows_enabled && var.victoriametrics_enabled && var.prometheus_operator_crds_enabled ? 1 : 0

  metadata {
    name      = "argo-workflows-grafana-dashboard"
    namespace = "victoriametrics"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "argo-workflows-dashboard.json" = data.http.argo_workflows_grafana_dashboard[0].response_body
  }

  depends_on = [
    helm_release.argo_workflows
  ]
}

# Auto-create S3 bucket for Argo Workflows artifacts when enabled
resource "minio_s3_bucket" "argo_workflows_artifacts" {
  count = var.argo_workflows_enabled && var.argo_workflows_artifact_s3_enabled && var.argo_workflows_artifact_s3_bucket == null ? 1 : 0

  bucket         = "${var.cluster_name}-argo-workflows-artifacts"
  acl            = "private"
  object_locking = false
}

resource "minio_ilm_policy" "argo_workflows_artifacts" {
  count = var.argo_workflows_enabled && var.argo_workflows_artifact_s3_enabled && var.argo_workflows_artifact_s3_bucket == null ? 1 : 0

  bucket = minio_s3_bucket.argo_workflows_artifacts[0].bucket

  rule {
    id         = "expire-30d"
    status     = "Enabled"
    expiration = "30d"
  }
}
