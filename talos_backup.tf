locals {
  # Use auto-created bucket name if bucket is not explicitly provided
  talos_backup_s3_bucket_name = var.talos_backup_s3_bucket != null ? var.talos_backup_s3_bucket : (
    var.talos_backup_s3_enabled ? "${var.cluster_name}-talos-backup" : null
  )

  talos_backup_s3_bucket   = local.talos_backup_s3_bucket_name
  talos_backup_s3_location = coalesce(var.s3_location, local.control_plane_nodepools[0].location)
  talos_backup_s3_region   = var.talos_backup_s3_enabled ? local.location_to_zone[local.talos_backup_s3_location] : null
  talos_backup_s3_endpoint = var.talos_backup_s3_enabled ? "https://${local.talos_backup_s3_location}.your-objectstorage.com" : null

  talos_backup_service_account = {
    apiVersion = "talos.dev/v1alpha1"
    kind       = "ServiceAccount"
    metadata = {
      name      = "talos-backup-secrets"
      namespace = "kube-system"
    }
    spec = {
      roles = [
        "os:etcd:backup"
      ]
    }
  }

  talos_backup_s3_secrets = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "talos-backup-s3-secrets"
      namespace = "kube-system"
    }
    type = "Opaque"
    data = {
      access_key = base64encode(var.talos_backup_s3_enabled ? var.s3_admin_access_key : "")
      secret_key = base64encode(var.talos_backup_s3_enabled ? var.s3_admin_secret_key : "")
    }
  }

  talos_backup_cronjob = {
    apiVersion = "batch/v1"
    kind       = "CronJob"
    metadata = {
      name      = "talos-backup"
      namespace = "kube-system"
    }
    spec = {
      schedule          = var.talos_backup_schedule
      suspend           = local.talos_backup_s3_bucket == null
      concurrencyPolicy = "Forbid"
      jobTemplate = {
        spec = {
          template = {
            spec = {
              containers = [{
                name            = "talos-backup"
                image           = "ghcr.io/siderolabs/talos-backup:${var.talos_backup_version}"
                workingDir      = "/tmp"
                imagePullPolicy = "IfNotPresent"
                env = [
                  { name = "AWS_ACCESS_KEY_ID", valueFrom = { secretKeyRef = { name = "talos-backup-s3-secrets", key = "access_key" } } },
                  { name = "AWS_SECRET_ACCESS_KEY", valueFrom = { secretKeyRef = { name = "talos-backup-s3-secrets", key = "secret_key" } } },
                  { name = "AGE_X25519_PUBLIC_KEY", value = var.talos_backup_age_x25519_public_key },
                  { name = "DISABLE_ENCRYPTION", value = tostring(var.talos_backup_age_x25519_public_key == null) },
                  { name = "AWS_REGION", value = local.talos_backup_s3_region },
                  { name = "CUSTOM_S3_ENDPOINT", value = local.talos_backup_s3_endpoint },
                  { name = "BUCKET", value = local.talos_backup_s3_bucket },
                  { name = "CLUSTER_NAME", value = var.cluster_name },
                  { name = "S3_PREFIX", value = var.talos_backup_s3_prefix },
                  { name = "USE_PATH_STYLE", value = tostring(var.talos_backup_s3_path_style) }
                ]
                volumeMounts = [
                  { name = "tmp", mountPath = "/tmp" },
                  { name = "talos-secrets", mountPath = "/var/run/secrets/talos.dev" }
                ]
                resources = {
                  requests = { memory = "128Mi", cpu = "250m" }
                  limits   = { memory = "256Mi", cpu = "500m" }
                }
                securityContext = {
                  runAsUser                = 1000
                  runAsGroup               = 1000
                  allowPrivilegeEscalation = false
                  runAsNonRoot             = true
                  capabilities             = { drop = ["ALL"] }
                  seccompProfile           = { type = "RuntimeDefault" }
                }
              }]
              restartPolicy = "OnFailure"
              volumes = [
                { emptyDir = {}, name = "tmp" },
                { name = "talos-secrets", secret = { secretName = "talos-backup-secrets" } }
              ]
              tolerations = [
                { key = "node-role.kubernetes.io/control-plane", operator = "Exists", effect = "NoSchedule" }
              ]
            }
          }
        }
      }
    }
  }

  talos_backup_manifest = var.talos_backup_s3_enabled ? {
    name     = "talos-backup"
    contents = <<-EOF
      ${yamlencode(local.talos_backup_service_account)}
      ---
      ${yamlencode(local.talos_backup_s3_secrets)}
      ---
      ${yamlencode(local.talos_backup_cronjob)}
    EOF
  } : null
}

# Auto-create S3 bucket for Talos backup when enabled
resource "minio_s3_bucket" "talos_backup" {
  count = var.talos_backup_s3_enabled && var.talos_backup_s3_bucket == null ? 1 : 0

  bucket         = "${var.cluster_name}-talos-backup"
  acl            = "private"
  object_locking = false
}

resource "minio_ilm_policy" "talos_backup" {
  count = var.talos_backup_s3_enabled && var.talos_backup_s3_bucket == null ? 1 : 0

  bucket = minio_s3_bucket.talos_backup[0].bucket

  rule {
    id         = "expire-30d"
    status     = "Enabled"
    expiration = "30d"
  }
}
