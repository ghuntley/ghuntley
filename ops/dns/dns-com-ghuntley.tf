# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

resource "cloudflare_record" "com_ghuntley_apex" {
  zone_id = var.com_ghuntley_cloudflare_zone_id
  name    = "@"
  type    = "A"
  value   = var.com_ghuntley_ipv4
}

# resource "cloudflare_record" "com_ghuntley_apex_ipv6" {
#   zone_id = var.com_ghuntley_cloudflare_zone_id
#   name    = "@"
#   type    = "AAAA"
#   value   = var.com_ghuntley_ipv6
# }

/**
 * domain ownership verification
 */

 resource "cloudflare_record" "net_ghuntley_txt_google_site_verification" {
  zone_id = var.com_ghuntley_cloudflare_zone_id
  name    = "@"
  type    = "TXT"
  value   = "google-site-verification=Ygi199GbO9ipejg0519FZUH5JVbWB_qIS9JOke_ulp8"
}

 resource "cloudflare_record" "net_ghuntley_txt_keybase_site_verification" {
  zone_id = var.com_ghuntley_cloudflare_zone_id
  name    = "@"
  type    = "TXT"
  value   = "keybase-site-verification=qINp7lIpBcjEroqO0EFwILvIXlf1pWb0gpAEB3OhQn8"
}

resource "cloudflare_record" "net_ghuntley_txt_yandex_site_verification" {
  zone_id = var.com_ghuntley_cloudflare_zone_id
  name    = "@"
  type    = "TXT"
  value   = "yandex-verification: 13b44c9f1d9d0c8b"
}



/**
 * email
 */

resource "cloudflare_record" "com_ghuntley_txt_domainkey_google" {
  zone_id = var.com_ghuntley_cloudflare_zone_id
  name    = "google._domainkey"
  type    = "TXT"
  value   = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAjTJ9ixaYL4T3SUcX2UwDPGBlkHC00F/3jRUYtlka6YkwG8MOIP/+4YtWUYvHI0J2sAquOGmvAqGhGle/o4uJ9IoAqVutXiy26eOKV9Yqb51oWUUHf/4piz0eZuucnCC1bbooDWb5Md2cf027hSEYQbRo4JY7/nvSFxEOQKKKtUeX/S/zlHrEostnPPZR5agElixgY45dHQ4nQtS35Xt6dulEN58kmefy5WvNq6+EyE0g9z8XqdGnnyaztbgVC3e2CrwqZ6UxVma5FKGiOPsIUKK/iAWGQrl6XDZVtcrvsR/N9rxdkS1FZ3FeVBpvKFeOHhkdXLwsGe/mX7CIpl63uQIDAQAB"
}

resource "cloudflare_record" "com_ghuntley_txt_domainkey_mailgun" {
  zone_id = var.com_ghuntley_cloudflare_zone_id
  name    = "smtp._domainkey.mg"
  type    = "TXT"
  value   = "k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCv7HfTuGalmhFiP/6duR/HeOxaZUR36leGQvZAQF5xjsLPZ2M2phiGZhyMla2mqh+jT1QqzW3GcHpYmkjhX1nZ7022tMGCx4j5SzbegDN3Vq/G4D/jiEcKQKEBnT7nCP/yorPCw4shcsmV/QlXhMM0sZjNcZF/yMooiupwCieKAwIDAQAB"
}

resource "cloudflare_record" "com_ghuntley_txt_dmarc" {
  zone_id = var.com_ghuntley_cloudflare_zone_id
  name    = "_dmarc"
  type    = "TXT"
  value   = "v=DMARC1; p=none; rua=mailto:ghuntley+dmarc@ghuntley.com"
}

resource "cloudflare_record" "com_ghuntley_txt_spf" {
  zone_id = var.com_ghuntley_cloudflare_zone_id
  name    = "@"
  type    = "TXT"
  value   = "v=spf1 include:_spf.google.com ~all"
}

resource "cloudflare_record" "com_ghuntley_txt_spf_mailgun" {
  zone_id = var.com_ghuntley_cloudflare_zone_id
  name    = "mg"
  type    = "TXT"
  value   = "v=spf1 include:mailgun.org ~all"
}

resource "cloudflare_record" "com_ghuntley_mx_mailgun_a" {
  zone_id  = var.com_ghuntley_cloudflare_zone_id
  name     = "mg"
  type     = "MX"
  value    = "mxa.mailgun.org"
  priority = 10
}

resource "cloudflare_record" "com_ghuntley_mx_mailgun_b" {
  zone_id  = var.com_ghuntley_cloudflare_zone_id
  name     = "mg"
  type     = "MX"
  value    = "mxb.mailgun.org"
  priority = 10
}

resource "cloudflare_record" "com_ghuntley_mx_1" {
  zone_id  = var.com_ghuntley_cloudflare_zone_id
  name     = "@"
  type     = "MX"
  value    = "aspmx.l.google.com"
  priority = 1
}

resource "cloudflare_record" "com_ghuntley_mx_5_1" {
  zone_id  = var.com_ghuntley_cloudflare_zone_id
  name     = "@"
  type     = "MX"
  value    = "alt1.aspmx.l.google.com"
  priority = 5
}

resource "cloudflare_record" "com_ghuntley_mx_5_2" {
  zone_id  = var.com_ghuntley_cloudflare_zone_id
  name     = "@"
  type     = "MX"
  value    = "alt2.aspmx.l.google.com"
  priority = 5
}

resource "cloudflare_record" "com_ghuntley_mx_10_1" {
  zone_id  = var.com_ghuntley_cloudflare_zone_id
  name     = "@"
  type     = "MX"
  value    = "alt3.aspmx.l.google.com"
  priority = 5
}

resource "cloudflare_record" "com_ghuntley_mx_10_2" {
  zone_id  = var.com_ghuntley_cloudflare_zone_id
  name     = "@"
  type     = "MX"
  value    = "alt4.aspmx.l.google.com"
  priority = 5
}

# records

resource "cloudflare_record" "com_ghuntley_fediverse" {
  zone_id = var.com_ghuntley_cloudflare_zone_id
  name    = "fediverse"
  type    = "A"
  value   = var.com_ghuntley_ipv4
}

# resource "cloudflare_record" "com_ghuntley_fediverse_ipv6" {
#   zone_id = var.com_ghuntley_cloudflare_zone_id
#   name    = "fediverse"
#   type    = "AAAA"
#   value   = var.com_ghuntley_ipv6
# }

resource "cloudflare_record" "com_ghuntley_mg_email" {
  zone_id = var.com_ghuntley_cloudflare_zone_id
  name    = "email.mg"
  type    = "CNAME"
  value   = "mailgun.org"
}

resource "cloudflare_record" "com_ghuntley_www" {
  zone_id = var.com_ghuntley_cloudflare_zone_id
  name    = "www"
  type    = "A"
  value   = var.com_ghuntley_ipv4
}

# resource "cloudflare_record" "com_ghuntley_www_ipv6" {
#   zone_id = var.com_ghuntley_cloudflare_zone_id
#   name    = "www"
#   type    = "AAAA"
#   value   = var.com_ghuntley_ipv6
# }
