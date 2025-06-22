locals {
  talos_tailscale_manifest = var.talos_tailscale_enabled ? {
    name     = "tailscale"
    contents = yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ExtensionServiceConfig"
      name       = "tailscale"
      environment = compact(concat(
        var.talos_tailscale_authkey != null ? ["TS_AUTHKEY=${var.talos_tailscale_authkey}"] : [],
        [for k, v in var.talos_tailscale_extra_env : "${k}=${v}"]
      ))
    })
  } : null
}
