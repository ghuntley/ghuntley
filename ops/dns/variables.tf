/**
 * Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 * SPDX-License-Identifier: Proprietary
 */

# cloudflare

variable "cloudflare_email" {
  type      = string
  sensitive = true
}

variable "cloudflare_api_key" {
  type      = string
  sensitive = true
}

variable "com_fediversehosting_cloudflare_zone_id" {
  type      = string
  sensitive = true
}

variable "com_fediversehosting_dmarc" {
  type      = string
  sensitive = true
}

# hosts

variable "dev_ipv4" {
  type      = string
  sensitive = true
}

variable "dev_ipv6" {
  type    = string
  sensitive = true
}
