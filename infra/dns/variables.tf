# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

variable "com_ponderoos_cloudflare_zone_id" {
  description = "Cloudflare Zone ID for ponderoos.com domain"
  type        = string
  sensitive   = true
}

variable "com_ponderoos_ipv4" {
  description = "IPv4 address for ponderoos.com A records"
  type        = string
}