/**
 * Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 * SPDX-License-Identifier: Proprietary
 */

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
    }
  }

  backend "gcs" {
    bucket = "tfstate-prod-fediversehosting"
    prefix = "terraform/bucket-tfstate-prod-fediversehosting"
  }
}

provider "google" {
  project = "fediversehosting-com"
  region  = "australia-southeast1"
}

resource "google_storage_bucket" "tfstate-prod-fediversehosting" {
  name          = "tfstate-prod-fediversehosting"
  location      = "asia"
  force_destroy = true
  versioning {
    enabled = true
  }
}
