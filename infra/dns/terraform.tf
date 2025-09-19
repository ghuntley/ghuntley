# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

terraform {
  required_version = ">= 1.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 3.0"
    }
  }

  backend "s3" {
    # Configuration provided via environment variables:
    # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_S3_ENDPOINT
    bucket                      = "otter-tfstate"
    key                         = "dns/terraform.tfstate"
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}