# Copyright (c) 2025 Ponderoos <support@ponderoos.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# All Keycloak clients, that is applications which authenticate
# through Keycloak.
#
# Includes first-party (i.e. ponderoos-hosted) and third-party clients.

resource "keycloak_openid_client" "grafana" {
  realm_id              = keycloak_realm.ponderoos.id
  client_id             = "grafana"
  name                  = "Grafana"
  enabled               = true
  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true
  base_url              = "https://status.ponderoos.com"

  valid_redirect_uris = [
    "https://status.ponderoos.com/*",
  ]
}

resource "keycloak_openid_client" "gerrit" {
  realm_id                                 = keycloak_realm.ponderoos.id
  client_id                                = "gerrit"
  name                                     = "Ponderoos Gerrit"
  enabled                                  = true
  access_type                              = "CONFIDENTIAL"
  standard_flow_enabled                    = true
  base_url                                 = "https://cl.ponderoos.com"
  description                              = "Ponderoos' code review tool"
  direct_access_grants_enabled             = true
  exclude_session_state_from_auth_response = false

  valid_redirect_uris = [
    "https://cl.ponderoos.com/*",
  ]

  web_origins = [
    "https://cl.ponderoos.com",
  ]
}
