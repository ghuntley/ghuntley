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

variable "com_ghuntley_cloudflare_zone_id" {
  type      = string
  sensitive = true
}

variable "dev_ghuntley_cloudflare_zone_id" {
  type      = string
  sensitive = true
}

variable "net_ghuntley_cloudflare_zone_id" {
  type      = string
  sensitive = true
}

# hosts

variable "com_ghuntley_ipv4" {
  type      = string
  sensitive = true
}

variable "com_ghuntley_ipv6" {
  type      = string
  sensitive = true
}

variable "dev_ghuntley_ipv4" {
  type      = string
  sensitive = true
}

variable "dev_ghuntley_ipv6" {
  type      = string
  sensitive = true
}

variable "net_ghuntley_ipv4" {
  type    = string
  sensitive = true
}

variable "net_ghuntley_ipv6" {
  type    = string
  sensitive = true
}
