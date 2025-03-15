# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

resource "cloudflare_record" "com_lhuntley_apex_1" {
  zone_id = var.com_lhuntley_cloudflare_zone_id
  name    = "@"
  type    = "A"
  value   = "185.199.108.153"
  proxied = false
}

resource "cloudflare_record" "com_lhuntley_apex_2" {
  zone_id = var.com_lhuntley_cloudflare_zone_id
  name    = "@"
  type    = "A"
  value   = "185.199.109.153"
  proxied = false
}

resource "cloudflare_record" "com_lhuntley_apex_3" {
  zone_id = var.com_lhuntley_cloudflare_zone_id
  name    = "@"
  type    = "A"
  value   = "185.199.110.153"
  proxied = false
}

resource "cloudflare_record" "com_lhuntley_apex_4" {
  zone_id = var.com_lhuntley_cloudflare_zone_id
  name    = "@"
  type    = "A"
  value   = "185.199.111.153"
  proxied = false
}


resource "cloudflare_record" "com_lhuntley_wildcard" {
  zone_id = var.com_lhuntley_cloudflare_zone_id
  name    = "*.lhuntley.com"
  type    = "A"
  value   = var.com_lhuntley_ipv4
  proxied = false
}
