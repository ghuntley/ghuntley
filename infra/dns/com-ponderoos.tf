# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

/**
 * domain ownership verification
 */


/**
 * email
 */


/**
 * records
 */

resource "cloudflare_dns_record" "com_ponderoos_apex" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "@"
  type    = "A"
  content = var.com_ponderoos_ipv4
  ttl     = 3600
  proxied = false
}


resource "cloudflare_dns_record" "com_ponderoos_www" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "www"
  type    = "A"
  content = var.com_ponderoos_ipv4
  ttl     = 3600
  proxied = false
}

resource "cloudflare_dns_record" "com_ponderoos_auth" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "auth"
  type    = "A"
  content = var.com_ponderoos_ipv4
  ttl     = 3600
  proxied = false
}

resource "cloudflare_dns_record" "com_ponderoos_packages" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "packages"
  type    = "A"
  content = var.com_ponderoos_ipv4
  ttl     = 3600
  proxied = false
}

resource "cloudflare_dns_record" "com_ponderoos_api" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "api"
  type    = "A"
  content = var.com_ponderoos_ipv4
  ttl     = 3600
  proxied = false
}