# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

terraform {
  required_providers {
    buildkite = {
      source  = "buildkite/buildkite"
      version = "~> 1.8.0"
    }
  }

  backend "s3" {
    endpoints = {
      s3 = "https://s3.eu-west-par.io.cloud.ovh.net/"
    }
    bucket = "ponderoos-terraform"
    key    = "buildkite/terraform.tfstate"
    region = "eu-west-par"

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}

provider "buildkite" {
  # Configure the Buildkite Provider
  api_token    = var.buildkite_api_token
  organization = "ponderoos"
}

# Variables
variable "buildkite_api_token" {
  description = "Buildkite API token"
  type        = string
  sensitive   = true
}

# Read pipeline configuration from YAML file
data "local_file" "steps_depot" {
  filename = "${path.module}/steps-depot.yaml"
}

# Create the cluster
resource "buildkite_cluster" "primary" {
  name        = "Ponderoos"
  description = "Runs the monolith build and deploy"
  emoji       = "🚀"
  color       = "#bada55"
}

# create a queue to put pipeline builds in
resource "buildkite_cluster_queue" "x64" {
  cluster_id = buildkite_cluster.primary.id
  key        = "x64"
}

resource "buildkite_cluster_default_queue" "x64" {
  cluster_id = buildkite_cluster.primary.id
  queue_id   = buildkite_cluster_queue.x64.id
}

# Create the pipeline
resource "buildkite_pipeline" "depot" {
  name        = "depot"
  repository = "https://cl.ponderoos.com/depot"
  description = "ponderoos monorepo"
  cluster_id = buildkite_cluster.primary.id

  # Use the YAML configuration from the external file
  steps = data.local_file.steps_depot.content

  # Default pipeline settings
  default_branch = "trunk"
}
