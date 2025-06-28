output "talosconfig" {
  description = "Configuration data for Talos OS"
  value       = local.talosconfig
  sensitive   = true
}

output "kubeconfig" {
  description = "Kubeconfig data used for cluster authentication"
  value       = local.kubeconfig
  sensitive   = true
}

output "kubeconfig_data" {
  description = "Structured kubeconfig data to supply to other providers"
  value       = local.kubeconfig_data
  sensitive   = true
}

output "talosconfig_data" {
  description = "Structured talosconfig data to supply to other providers"
  value       = local.talosconfig_data
  sensitive   = true
}

output "talos_client_configuration" {
  description = "Talos client configuration details"
  value       = data.talos_client_configuration.this
}

output "talos_machine_configurations_control_plane" {
  description = "Talos machine configurations for control plane nodes"
  value       = data.talos_machine_configuration.control_plane
  sensitive   = true
}

output "talos_machine_configurations_worker" {
  description = "Talos machine configurations for worker nodes"
  value       = data.talos_machine_configuration.worker
  sensitive   = true
}

output "control_plane_private_ipv4_list" {
  description = "Private IPv4 addresses of all control plane nodes"
  value       = local.control_plane_private_ipv4_list
}

output "control_plane_public_ipv4_list" {
  description = "Public IPv4 addresses of all control plane nodes"
  value       = local.control_plane_public_ipv4_list
}

output "control_plane_public_ipv6_list" {
  description = "Public IPv6 addresses of all control plane nodes"
  value       = local.control_plane_public_ipv6_list
}

output "worker_private_ipv4_list" {
  description = "Private IPv4 addresses of all worker nodes"
  value       = local.worker_private_ipv4_list
}

output "worker_public_ipv4_list" {
  description = "Public IPv4 addresses of all worker nodes"
  value       = local.worker_public_ipv4_list
}

output "worker_public_ipv6_list" {
  description = "Public IPv6 addresses of all worker nodes"
  value       = local.worker_public_ipv6_list
}

output "tailscale_operator_enabled" {
  description = "Whether Tailscale Kubernetes Operator is enabled"
  value       = var.tailscale_enabled
}

output "tailscale_urls" {
  description = "Tailscale URLs for enabled services"
  value = {
    argocd                       = var.argocd_enabled && var.tailscale_enabled && var.argocd_tailscale_ingress_enabled ? "https://${coalesce(var.argocd_tailscale_hostname, "${var.cluster_name}-argocd")}.${var.tailscale_tailnet}" : null
    argo_workflows               = var.argo_workflows_enabled && var.tailscale_enabled && var.argo_workflows_tailscale_ingress_enabled ? "https://${coalesce(var.argo_workflows_tailscale_hostname, "${var.cluster_name}-argo-workflows")}.${var.tailscale_tailnet}" : null
    kubetail                     = var.kubetail_enabled && var.tailscale_enabled && var.kubetail_tailscale_ingress_enabled ? "https://${coalesce(var.kubetail_tailscale_hostname, "${var.cluster_name}-kubetail")}.${var.tailscale_tailnet}" : null
    longhorn                     = var.longhorn_enabled && var.tailscale_enabled && var.longhorn_tailscale_ingress_enabled ? "https://${coalesce(var.longhorn_tailscale_hostname, "${var.cluster_name}-longhorn")}.${var.tailscale_tailnet}" : null
    victoriametrics              = var.victoriametrics_enabled && var.tailscale_enabled && var.victoriametrics_tailscale_ingress_enabled ? "https://${coalesce(var.victoriametrics_tailscale_hostname, "${var.cluster_name}-victoriametrics")}.${var.tailscale_tailnet}" : null
    victoriametrics_grafana      = var.victoriametrics_enabled && var.tailscale_enabled && var.victoriametrics_tailscale_ingress_enabled ? "https://${coalesce(var.victoriametrics_grafana_tailscale_hostname, "${var.cluster_name}-grafana")}.${var.tailscale_tailnet}" : null
    victoriametrics_vmalert      = var.victoriametrics_enabled && var.tailscale_enabled && var.victoriametrics_tailscale_ingress_enabled ? "https://${coalesce(var.victoriametrics_vmalert_tailscale_hostname, "${var.cluster_name}-vmalert")}.${var.tailscale_tailnet}" : null
    victoriametrics_vmagent      = var.victoriametrics_enabled && var.tailscale_enabled && var.victoriametrics_tailscale_ingress_enabled ? "https://${coalesce(var.victoriametrics_vmagent_tailscale_hostname, "${var.cluster_name}-vmagent")}.${var.tailscale_tailnet}" : null
    victoriametrics_alertmanager = var.victoriametrics_enabled && var.tailscale_enabled && var.victoriametrics_tailscale_ingress_enabled ? "https://${coalesce(var.victoriametrics_alertmanager_tailscale_hostname, "${var.cluster_name}-alertmanager")}.${var.tailscale_tailnet}" : null
    victorialogs                 = var.victorialogs_enabled && var.tailscale_enabled && var.victorialogs_tailscale_ingress_enabled ? "https://${coalesce(var.victorialogs_tailscale_hostname, "${var.cluster_name}-victorialogs")}.${var.tailscale_tailnet}" : null
  }
}

output "minio_client_config" {
  description = "MinIO client configuration for S3 access"
  value       = local.minio_client_config
  sensitive   = true
}
