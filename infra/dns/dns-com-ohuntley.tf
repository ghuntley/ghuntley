# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

resource "cloudflare_record" "com_ohuntley_apex_1" {
  zone_id = var.com_ohuntley_cloudflare_zone_id
  name    = "@"
  type    = "A"
  value   = "185.199.108.153"
  proxied = false
}

resource "cloudflare_record" "com_ohuntley_apex_2" {
  zone_id = var.com_ohuntley_cloudflare_zone_id
  name    = "@"
  type    = "A"
  value   = "185.199.109.153"
  proxied = false
}

resource "cloudflare_record" "com_ohuntley_apex_3" {
  zone_id = var.com_ohuntley_cloudflare_zone_id
  name    = "@"
  type    = "A"
  value   = "185.199.110.153"
  proxied = false
}

resource "cloudflare_record" "com_ohuntley_apex_4" {
  zone_id = var.com_ohuntley_cloudflare_zone_id
  name    = "@"
  type    = "A"
  value   = "185.199.111.153"
  proxied = false
}


resource "cloudflare_record" "com_ohuntley_wildcard" {
  zone_id = var.com_ohuntley_cloudflare_zone_id
  name    = "*.ohuntley.com"
  type    = "A"
  value   = var.com_ohuntley_ipv4
  proxied = false
}

resource "cloudflare_record" "com_ohuntley_mia" {
  zone_id = var.com_ohuntley_cloudflare_zone_id
  name    = "mia"
  type    = "A"
  value   = var.com_ponderoos_ingress_ipv4
  proxied = false
}
