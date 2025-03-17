# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

resource "cloudflare_record" "com_ponderoos_apex" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "@"
  type    = "A"
  value   = var.com_ponderoos_ipv4
  proxied = false
}

/**
 * domain ownership verification
 */


/**
 * email
 */

resource "cloudflare_record" "com_ponderoos_txt_domainkey" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "mail._domainkey"
  type    = "TXT"
  value   = "v=DKIM1; k=rsa; s=email; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDJMrmJFa1hg3+pGH+LftAdVnT9Wro0zTQi0lYwW2gyKJhdW3sU+/g5Yb9a3bheV211MqhK8imspS+e0Qqpvhf4N13BDBUg497IIEDFeX2HEJNLDjimO7jnUV7b1zuFW4tyqWZfaQUR6Zg/5LCKYig+HoMcCxK+Sc8+11Vku9ubiQIDAQAB"
}

resource "cloudflare_record" "com_ponderoos_txt_dmarc" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "_dmarc"
  type    = "TXT"
  value   = "v=DMARC1; p=none; rua=mailto:support@ponderoos.com"
}

resource "cloudflare_record" "com_ponderoos_txt_spf" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "@"
  type    = "TXT"
  value   = "v=spf1 a:mail.ponderoos.com -all"
}

resource "cloudflare_record" "com_ponderoos_mx_10" {
  zone_id  = var.com_ponderoos_cloudflare_zone_id
  name     = "@"
  type     = "MX"
  value    = "mail.ponderoos.com"
  priority = 5
}

resource "cloudflare_record" "com_ponderoos_srv_smtp_submission" {
  zone_id  = var.com_ponderoos_cloudflare_zone_id
  name     = "_submission._tcp"
  type     = "SRV"
  data {
    priority = 5
    weight   = 0
    port     = 587
    target   = "mail.ponderoos.com"
  }
  ttl = 3600
}

resource "cloudflare_record" "com_ponderoos_srv_smtp_submissions" {
  zone_id  = var.com_ponderoos_cloudflare_zone_id
  name     = "_submissions._tcp"
  type     = "SRV"
  data {
    priority = 5
    weight   = 0
    port     = 465
    target   = "mail.ponderoos.com"
  }
  ttl = 3600
}

resource "cloudflare_record" "com_ponderoos_srv_imap" {
  zone_id  = var.com_ponderoos_cloudflare_zone_id
  name     = "_imap._tcp"
  type     = "SRV"
  data {
    priority = 5
    weight   = 0
    port     = 143
    target   = "mail.ponderoos.com"
  }
  ttl = 3600
}

resource "cloudflare_record" "com_ponderoos_srv_imaps" {
  zone_id  = var.com_ponderoos_cloudflare_zone_id
  name     = "_imaps._tcp"
  type     = "SRV"
  data {
    priority = 5
    weight   = 0
    port     = 993
    target   = "mail.ponderoos.com"
  }
  ttl = 3600
}

# records

resource "cloudflare_record" "com_ponderoos_mail" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "mail"
  type    = "A"
  value   = var.com_ponderoos_ipv4
  proxied = false
}

resource "cloudflare_record" "com_ponderoos_smtp" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "smtp"
  type    = "A"
  value   = var.com_ponderoos_ipv4
  proxied = false
}

resource "cloudflare_record" "com_ponderoos_imap" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "imap"
  type    = "A"
  value   = var.com_ponderoos_ipv4
  proxied = false
}

resource "cloudflare_record" "com_ponderoos_pop3" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "pop3"
  type    = "A"
  value   = var.com_ponderoos_ipv4
  proxied = false
}

resource "cloudflare_record" "com_ponderoos_www" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "www"
  type    = "A"
  value   = var.com_ponderoos_ipv4
  proxied = false
}


resource "cloudflare_record" "com_ponderoos_nix_cache" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "nix-cache"
  type    = "A"
  value   = var.com_ponderoos_ipv4
  proxied = false
}

resource "cloudflare_record" "com_ponderoos_upterm" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "upterm"
  type    = "A"
  value   = var.com_ponderoos_ipv4
  proxied = false
}

resource "cloudflare_record" "com_ponderoos_vault" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "vault"
  type    = "A"
  value   = var.com_ponderoos_ipv4
  proxied = false
}


resource "cloudflare_record" "com_ponderoos_pxe" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "pxe"
  type    = "A"
  value   = var.com_ponderoos_ipv4
  proxied = false
}

resource "cloudflare_record" "com_ponderoos_ingress" {
  zone_id = var.com_ponderoos_cloudflare_zone_id
  name    = "ingress"
  type    = "A"
  value   = var.com_ponderoos_ingress_ipv4
  proxied = false
}
