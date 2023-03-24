/**
 * Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 * SPDX-License-Identifier: Proprietary
 */

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
    }
    google = {
      source  = "hashicorp/google"
    }
  }

  backend "gcs" {
    bucket = "tfstate-ghuntley-net"
    prefix = "terraform/dns"
  }
}

provider "cloudflare" {
  email   = var.cloudflare_email
  api_key = var.cloudflare_api_key
}

provider "google" {
  project = "ghuntley-net"
  region  = "australia-southeast1"
}
