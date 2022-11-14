# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

resource "cloudflare_record" "com_fediversehosting_apex_A" {
  zone_id = var.com_fediversehosting_cloudflare_zone_id
  name    = "@"
  type    = "A"
  value   = var.dev_ipv4
}

resource "cloudflare_record" "com_fediversehosting_apex_AAA" {
  zone_id = var.com_fediversehosting_cloudflare_zone_id
  name    = "@"
  type    = "AAA"
  value   = var.dev_ipv6
}

/**
 * domain ownership verification
 */


/**
 * email
 */

resource "cloudflare_record" "com_fediversehosting_txt_dkim" {
  zone_id = var.com_fediversehosting_cloudflare_zone_id
  name    = "@"
  type    = "TXT"
  value   = "TODO: Configure DKIM for 21kbh"
}

resource "cloudflare_record" "com_fediversehosting_txt_dmarc" {
  zone_id = var.com_fediversehosting_cloudflare_zone_id
  name    = "@"
  type    = "TXT"
  value   = var.com_fediversehosting_dmarc
}

resource "cloudflare_record" "com_fediversehosting_txt_spf" {
  zone_id = var.com_fediversehosting_cloudflare_zone_id
  name    = "@"
  type    = "TXT"
  value   = "v=spf1 include:_spf.google.com ~all"
}

resource "cloudflare_record" "com_fediversehosting_mx_1" {
  zone_id  = var.com_fediversehosting_cloudflare_zone_id
  name     = "@"
  type     = "MX"
  value    = "aspmx.l.google.com"
  priority = 1
}

resource "cloudflare_record" "com_fediversehosting_mx_5_1" {
  zone_id  = var.com_fediversehosting_cloudflare_zone_id
  name     = "@"
  type     = "MX"
  value    = "alt1.aspmx.l.google.com"
  priority = 5
}

resource "cloudflare_record" "com_fediversehosting_mx_5_2" {
  zone_id  = var.com_fediversehosting_cloudflare_zone_id
  name     = "@"
  type     = "MX"
  value    = "alt2.aspmx.l.google.com"
  priority = 5
}

resource "cloudflare_record" "com_fediversehosting_mx_10_1" {
  zone_id  = var.com_fediversehosting_cloudflare_zone_id
  name     = "@"
  type     = "MX"
  value    = "alt3.aspmx.l.google.com"
  priority = 5
}

resource "cloudflare_record" "com_fediversehosting_mx_10_2" {
  zone_id  = var.com_fediversehosting_cloudflare_zone_id
  name     = "@"
  type     = "MX"
  value    = "alt4.aspmx.l.google.com"
  priority = 5
}

# records

resource "cloudflare_record" "com_fediversehosting_www" {
  zone_id = var.com_fediversehosting_cloudflare_zone_id
  name    = "www"
  type    = "A"
  value   = var.dev_ipv4
}

resource "cloudflare_record" "com_fediversehosting_auth" {
  zone_id = var.com_fediversehosting_cloudflare_zone_id
  name    = "auth"
  type    = "A"
  value   = var.dev_ipv4
}

resource "cloudflare_record" "com_fediversehosting_at" {
  zone_id = var.com_fediversehosting_cloudflare_zone_id
  name    = "at"
  type    = "A"
  value   = var.dev_ipv4
}

resource "cloudflare_record" "com_fediversehosting_status" {
  zone_id = var.com_fediversehosting_cloudflare_zone_id
  name    = "status"
  type    = "A"
  value   = var.dev_ipv4
}
