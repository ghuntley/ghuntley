# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

resource "cloudflare_record" "net_ghuntley_apex" {
  zone_id = var.net_ghuntley_cloudflare_zone_id
  name    = "@"
  type    = "A"
  value   = var.net_ghuntley_ipv4
  proxied = true
}

# resource "cloudflare_record" "net_ghuntley_apex_ipv6" {
#   zone_id = var.net_ghuntley_cloudflare_zone_id
#   name    = "@"
#   type    = "AAAA"
#   value   = var.net_ghuntley_ipv6
# }

/**
 * domain ownership verification
 */


/**
 * email
 */

resource "cloudflare_record" "net_ghuntley_txt_google_domainkey" {
  zone_id = var.net_ghuntley_cloudflare_zone_id
  name    = "google._domainkey"
  type    = "TXT"
  value   = "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCgoXN71FIF9uJQI7jcD6OwsUXtgwqqtn9aK+cFekpP995w6haBNEI7gQPPEN4fiyvYJ0j6GmqMzOAdQNqseXYS2fEg7D2doZxNu6cA/VNd06XvhIKDvrKsdTkan9IgHuE3Ocrh/zMYNML4o4KvuAdb7ryGBTah7EEf5//MlWREpQIDAQAB"
}

resource "cloudflare_record" "net_ghuntley_txt_dmarc" {
  zone_id = var.net_ghuntley_cloudflare_zone_id
  name    = "_dmarc"
  type    = "TXT"
  value   = "v=DMARC1; p=none; rua=mailto:ghuntley+dmarc@ghuntley.com"
}

resource "cloudflare_record" "net_ghuntley_txt_spf" {
  zone_id = var.net_ghuntley_cloudflare_zone_id
  name    = "@"
  type    = "TXT"
  value   = "v=spf1 include:_spf.google.com ~all"
}

resource "cloudflare_record" "net_ghuntley_mx_1" {
  zone_id  = var.net_ghuntley_cloudflare_zone_id
  name     = "@"
  type     = "MX"
  value    = "aspmx.l.google.com"
  priority = 1
}

resource "cloudflare_record" "net_ghuntley_mx_5_1" {
  zone_id  = var.net_ghuntley_cloudflare_zone_id
  name     = "@"
  type     = "MX"
  value    = "alt1.aspmx.l.google.com"
  priority = 5
}

resource "cloudflare_record" "net_ghuntley_mx_5_2" {
  zone_id  = var.net_ghuntley_cloudflare_zone_id
  name     = "@"
  type     = "MX"
  value    = "alt2.aspmx.l.google.com"
  priority = 5
}

resource "cloudflare_record" "net_ghuntley_mx_10_1" {
  zone_id  = var.net_ghuntley_cloudflare_zone_id
  name     = "@"
  type     = "MX"
  value    = "alt3.aspmx.l.google.com"
  priority = 5
}

resource "cloudflare_record" "net_ghuntley_mx_10_2" {
  zone_id  = var.net_ghuntley_cloudflare_zone_id
  name     = "@"
  type     = "MX"
  value    = "alt4.aspmx.l.google.com"
  priority = 5
}

# records

resource "cloudflare_record" "net_ghuntley_www" {
  zone_id = var.net_ghuntley_cloudflare_zone_id
  name    = "www"
  type    = "A"
  value   = var.net_ghuntley_ipv4
  proxied = true
}

# resource "cloudflare_record" "net_ghuntley_www_ipv6" {
#   zone_id = var.net_ghuntley_cloudflare_zone_id
#   name    = "www"
#   type    = "AAAA"
#   value   = var.net_ghuntley_ipv6
# }
