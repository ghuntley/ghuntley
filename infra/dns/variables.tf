/**
 * Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
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

# zones

variable "com_ponderoos_cloudflare_zone_id" {
  type      = string
  sensitive = true
}

variable "com_ghuntley_cloudflare_zone_id" {
  type      = string
  sensitive = true
}

variable "com_lhuntley_cloudflare_zone_id" {
  type      = string
  sensitive = true
}

variable "com_ohuntley_cloudflare_zone_id" {
  type      = string
  sensitive = true
}

variable "net_ghuntley_cloudflare_zone_id" {
  type      = string
  sensitive = true
}

variable "dev_ghuntley_cloudflare_zone_id" {
  type      = string
  sensitive = true
}

# hosts
variable "com_ponderoos_ipv4" {
  type      = string
  sensitive = true
}

variable "com_ghuntley_ipv4" {
  type      = string
  sensitive = true
}

variable "com_lhuntley_ipv4" {
  type      = string
  sensitive = true
}

variable "com_ohuntley_ipv4" {
  type      = string
  sensitive = true
}

variable "dev_ghuntley_ipv4" {
  type      = string
  sensitive = true
}

variable "net_ghuntley_ipv4" {
  type      = string
  sensitive = true
}
