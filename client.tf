locals {
  kubeconfig = replace(
    talos_cluster_kubeconfig.this.kubeconfig_raw,
    "/(\\s+server:).*/",
    "$1 ${local.kube_api_url_external}"
  )
  talosconfig = data.talos_client_configuration.this.talos_config

  kubeconfig_data = {
    name   = var.cluster_name
    server = local.kube_api_url_external
    ca     = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate)
    cert   = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate)
    key    = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key)
  }

  talosconfig_data = {
    name      = data.talos_client_configuration.this.cluster_name
    endpoints = data.talos_client_configuration.this.endpoints
    ca        = base64decode(data.talos_client_configuration.this.client_configuration.ca_certificate)
    cert      = base64decode(data.talos_client_configuration.this.client_configuration.client_certificate)
    key       = base64decode(data.talos_client_configuration.this.client_configuration.client_key)
  }

  minio_client_config = var.talos_backup_s3_enabled || (var.longhorn_enabled && var.longhorn_backup_s3_enabled) || (var.argo_workflows_enabled && var.argo_workflows_artifact_s3_enabled) ? {
    version = "10"
    aliases = {
      "hetzner" = {
        url       = "https://${coalesce(var.s3_location, local.control_plane_nodepools[0].location)}.your-objectstorage.com"
        accessKey = var.s3_admin_access_key
        secretKey = var.s3_admin_secret_key
        api       = "S3v4"
        path      = "auto"
      }
    }
  } : null
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.talos_endpoints
  nodes                = [local.talos_primary_node_private_ipv4]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.talos_primary_endpoint

  depends_on = [talos_machine_configuration_apply.control_plane]
}

resource "terraform_data" "create_minio_config" {
  count = local.minio_client_config != null ? 1 : 0

  triggers_replace = [
    sha1(jsonencode(local.minio_client_config))
  ]

  provisioner "local-exec" {
    when    = create
    quiet   = true
    command = <<-EOT
      set -eu

      mkdir -p .mc
      printf '%s' "$MINIO_CONFIG_CONTENT" > .mc/config.json
      chmod 600 .mc/config.json
    EOT
    environment = {
      MINIO_CONFIG_CONTENT = jsonencode(local.minio_client_config)
    }
  }

  provisioner "local-exec" {
    when       = destroy
    quiet      = true
    on_failure = continue
    command    = <<-EOT
      set -eu

      if [ -f ".mc/config.json" ]; then
        cp -f ".mc/config.json" ".mc/config.json.bak"
      fi
    EOT
  }
}

resource "terraform_data" "create_talosconfig" {
  count = var.cluster_talosconfig_path != null ? 1 : 0

  triggers_replace = [
    sha1(local.talosconfig),
    var.cluster_talosconfig_path
  ]

  input = {
    cluster_talosconfig_path = var.cluster_talosconfig_path
  }

  provisioner "local-exec" {
    when    = create
    quiet   = true
    command = <<-EOT
      set -eu

      printf '%s' "$TALOSCONFIG_CONTENT" > "$CLUSTER_TALOSCONFIG_PATH"
    EOT
    environment = {
      TALOSCONFIG_CONTENT      = local.talosconfig
      CLUSTER_TALOSCONFIG_PATH = var.cluster_talosconfig_path
    }
  }

  provisioner "local-exec" {
    when       = destroy
    quiet      = true
    on_failure = continue
    command    = <<-EOT
      set -eu

      if [ -f "$CLUSTER_TALOSCONFIG_PATH" ]; then
        cp -f "$CLUSTER_TALOSCONFIG_PATH" "$CLUSTER_TALOSCONFIG_PATH.bak"
      fi
    EOT
    environment = {
      CLUSTER_TALOSCONFIG_PATH = self.input.cluster_talosconfig_path
    }
  }

  depends_on = [talos_machine_configuration_apply.control_plane]
}

resource "terraform_data" "create_kubeconfig" {
  count = var.cluster_kubeconfig_path != null ? 1 : 0

  triggers_replace = [
    sha1(local.kubeconfig),
    var.cluster_kubeconfig_path
  ]

  input = {
    cluster_kubeconfig_path = var.cluster_kubeconfig_path
  }

  provisioner "local-exec" {
    when    = create
    quiet   = true
    command = <<-EOT
      set -eu

      printf '%s' "$KUBECONFIG_CONTENT" > "$CLUSTER_KUBECONFIG_PATH"
    EOT
    environment = {
      KUBECONFIG_CONTENT      = local.kubeconfig
      CLUSTER_KUBECONFIG_PATH = var.cluster_kubeconfig_path
    }
  }

  provisioner "local-exec" {
    when       = destroy
    quiet      = true
    on_failure = continue
    command    = <<-EOT
      set -eu

      if [ -f "$CLUSTER_KUBECONFIG_PATH" ]; then
        cp -f "$CLUSTER_KUBECONFIG_PATH" "$CLUSTER_KUBECONFIG_PATH.bak"
      fi
    EOT
    environment = {
      CLUSTER_KUBECONFIG_PATH = self.input.cluster_kubeconfig_path
    }
  }

  depends_on = [talos_machine_configuration_apply.control_plane]
}
