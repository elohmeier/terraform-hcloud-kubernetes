locals {
  victorialogs_enabled                   = var.victorialogs_enabled
  victorialogs_tailscale_ingress_enabled = var.victorialogs_enabled && var.tailscale_enabled
  victorialogs_tailscale_hostname        = coalesce(var.victorialogs_tailscale_hostname, "${var.cluster_name}-victorialogs")

  victorialogs_values = {
    server = {
      persistentVolume = {
        enabled = true
        size    = "10Gi"
      }
      service = {
        clusterIP = "" # tailscale ingress compat
      }
      serviceMonitor = {
        enabled = true
      }
      ingress = {
        enabled          = local.victorialogs_tailscale_ingress_enabled
        ingressClassName = "tailscale"
        hosts = [{
          name = "${local.victorialogs_tailscale_hostname}.${var.tailscale_tailnet}"
          path = ["/"]
          port = "http"
        }]
        tls = [{
          hosts = ["${local.victorialogs_tailscale_hostname}.${var.tailscale_tailnet}"]
        }]
      }
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

    dashboards = {
      enabled = true
      labels = {
        grafana_dashboard = "1"
      }
      namespace = "victoriametrics"
    }

    vector = {
      enabled = true
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
      podHostNetwork = true
      dnsPolicy      = "ClusterFirstWithHostNet"

      # not detected yet due to host network
      podMonitor = {
        enabled = true
      }

      customConfig = {

        sources = {
          talos_kernel_logs = {
            type       = "socket"
            address    = "127.0.0.1:6050"
            mode       = "udp"
            max_length = 102400
            decoding = {
              codec = "json"
            }
            host_key = "__host"
          }
          talos_service_logs = {
            type       = "socket"
            address    = "127.0.0.1:6051"
            mode       = "udp"
            max_length = 102400
            decoding = {
              codec = "json"
            }
            host_key = "__host"
          }
        }

        transforms = {
          talos_kernel_logs_vlogs = {
            type   = "remap"
            inputs = ["talos_kernel_logs"]
            source = ".stream = \"kernel\"\n.__host = get_hostname!()"
          }
          talos_service_logs_vlogs = {
            type   = "remap"
            inputs = ["talos_service_logs"]
            source = ".stream = \"service\"\n.__host = get_hostname!()"
          }
        }

        sinks = {
          vlogs_kernel = {
            type        = "elasticsearch"
            inputs      = ["talos_kernel_logs_vlogs"]
            mode        = "bulk"
            api_version = "v8"
            compression = "gzip"
            healthcheck = {
              enabled = false
            }
            request = {
              headers = {
                VL-Time-Field    = "talos-time"
                VL-Stream-Fields = "stream,__host,facility"
                VL-Msg-Field     = "msg"
                AccountID        = "0"
                ProjectID        = "0"
              }
            }
          }
          vlogs_service = {
            type        = "elasticsearch"
            inputs      = ["talos_service_logs_vlogs"]
            mode        = "bulk"
            api_version = "v8"
            compression = "gzip"
            healthcheck = {
              enabled = false
            }
            request = {
              headers = {
                VL-Time-Field    = "talos-time"
                VL-Stream-Fields = "stream,__host,talos-service"
                VL-Msg-Field     = "msg"
                AccountID        = "0"
                ProjectID        = "0"
              }
            }
          }
        }

      }

      containerPorts = [
        {
          name          = "prom-exporter"
          containerPort = 9090
          protocol      = "TCP"
        },
        {
          name          = "talos-kernel"
          containerPort = 6050
          protocol      = "UDP"
        },
        {
          name          = "talos-service"
          containerPort = 6051
          protocol      = "UDP"
        }
      ]
    }
  }
}

resource "kubernetes_namespace_v1" "victorialogs" {
  count = var.victorialogs_enabled ? 1 : 0

  metadata {
    name = "victorialogs"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "helm_release" "victorialogs" {
  count = var.victorialogs_enabled ? 1 : 0

  name      = "vls"
  namespace = "victorialogs"

  repository       = var.victorialogs_helm_repository
  chart            = var.victorialogs_helm_chart
  version          = var.victorialogs_helm_version
  create_namespace = false
  wait             = false

  values = [
    yamlencode(
      merge(
        local.victorialogs_values,
        var.victorialogs_helm_values
      )
    )
  ]

  depends_on = [
    helm_release.cilium,
    kubernetes_namespace_v1.victorialogs,
  ]
}

resource "kubernetes_config_map_v1" "victorialogs_grafana_datasource" {
  count = var.victorialogs_enabled && var.victoriametrics_enabled ? 1 : 0

  metadata {
    name      = "victorialogs-datasource"
    namespace = "victoriametrics"
    labels = {
      grafana_datasource = "1"
    }
  }

  data = {
    "victorialogs-datasource.yaml" = yamlencode({
      apiVersion = 1
      datasources = [
        {
          name      = "VictoriaLogs"
          type      = "victoriametrics-logs-datasource"
          url       = "http://vls-victoria-logs-single-server.victorialogs.svc:9428"
          access    = "proxy"
          isDefault = false
        }
      ]
    })
  }

  depends_on = [
    kubernetes_namespace_v1.victoriametrics,
    helm_release.victorialogs,
  ]
}

resource "kubernetes_network_policy_v1" "vector_metrics_scrape" {
  count = var.victorialogs_enabled && var.victoriametrics_enabled ? 1 : 0

  metadata {
    name      = "allow-metrics-scrape-for-vector"
    namespace = "victorialogs"
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/component" = "Agent"
        "app.kubernetes.io/instance"  = "vls"
        "app.kubernetes.io/name"      = "vector"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "vmagent"
          }
        }
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "victoriametrics"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "9090"
      }
    }
  }

  depends_on = [
    kubernetes_namespace_v1.victorialogs,
    helm_release.victorialogs,
  ]
}
