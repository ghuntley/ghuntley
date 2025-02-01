# Copyright (c) 2025 Ponderoos <support@ponderoos.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Configure Ponderoos Keycloak instance.
#

terraform {
  required_providers {
    keycloak = {
      source = "mrparkers/keycloak"
    }
  }

  backend "s3" {
    endpoints = {
      s3 = "https://s3.eu-west-par.io.cloud.ovh.net/"
    }
    bucket = "ponderoos-terraform"
    key    = "keycloak/ponderoos/terraform.tfstate"
    region = "eu-west-par"

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}

provider "keycloak" {
  client_id = "terraform"
  url       = "https://auth.ponderoos.com"
  # NOTE: Docs mention this applies to "users of the legacy distribution of keycloak".
  # However, we get a "failed to perform initial login to Keycloak: error
  # sending POST request to https://auth.ponderoos.com/realms/master/protocol/openid-connect/token: 404 Not Found"
  # if we don't set this.
  base_path = "/auth"
}

resource "keycloak_realm" "ponderoos" {
  realm                       = "Ponderoos"
  enabled                     = true
  display_name                = "Ponderoos"
  default_signature_algorithm = "RS256"

  smtp_server {
    from              = "no-reply@ponderoos.com"
    from_display_name = "Keycloak"
    host              = "127.0.0.1"
    port              = "25"
    reply_to          = "support@ponderoos.com"
    ssl               = false
    starttls          = false
  }

  account_theme        = "keycloak.v2"
  access_code_lifespan = "30m"

  internationalization {
    supported_locales = [
      "en",
    ]

    default_locale = "en"
  }

  security_defenses {
    headers {
      x_frame_options                     = "DENY"
      content_security_policy             = "frame-src 'self'; frame-ancestors 'self'; object-src 'none';"
      content_security_policy_report_only = ""
      x_content_type_options              = "nosniff"
      x_robots_tag                        = "none"
      x_xss_protection                    = "1; mode=block"
      strict_transport_security           = "max-age=31536000; includeSubDomains"
    }

    brute_force_detection {
      permanent_lockout                = false
      max_login_failures               = 31
      wait_increment_seconds           = 61
      quick_login_check_milli_seconds  = 1000
      minimum_quick_login_wait_seconds = 120
      max_failure_wait_seconds         = 900
      failure_reset_time_seconds       = 43200
    }
  }

  web_authn_policy {
    relying_party_entity_name = "Ponderoos"
    relying_party_id          = "auth.ponderoos.com"
    signature_algorithms = [
      "ES256",
      "RS256"
    ]
  }

  web_authn_passwordless_policy {
    relying_party_entity_name = "Ponderoos"
    relying_party_id          = "auth.ponderoos.com"
    signature_algorithms = [
      "ES256",
      "RS256"
    ]
  }
}

# resource "keycloak_required_action" "required_action" {
#   realm_id = keycloak_realm.ponderoos.id
#   alias    = "webauthn-register"
#   enabled  = true
#   name     = "Webauthn Register"
# }
