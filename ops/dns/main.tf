/**
 * Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 * SPDX-License-Identifier: Proprietary
 */

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
    }
    aws = {
      source  = "hashicorp/aws"
    }
  }
}

provider "cloudflare" {
  email   = var.cloudflare_email
  api_key = var.cloudflare_api_key
}

provider "google" {
  project = "kbh-com"
  region  = "australia-southeast1"
}
