terraform {
  required_version = ">=1.7.0"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.8.1"
    }

    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.51.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0.2"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.5.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.37.1"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1.0"
    }

    minio = {
      source  = "aminueza/minio"
      version = "~> 3.5.3"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.0"
    }
  }
}

provider "minio" {
  minio_server   = "${coalesce(var.s3_location, local.control_plane_nodepools[0].location)}.your-objectstorage.com"
  minio_region   = coalesce(var.s3_location, local.control_plane_nodepools[0].location)
  minio_user     = var.s3_admin_access_key
  minio_password = var.s3_admin_secret_key
  minio_ssl      = true
}

provider "hcloud" {
  token         = var.hcloud_token
  poll_interval = "2s"
}

provider "kubernetes" {
  config_path = "kubeconfig"
}

provider "helm" {
  kubernetes = {
    config_path = "kubeconfig"
  }
}
