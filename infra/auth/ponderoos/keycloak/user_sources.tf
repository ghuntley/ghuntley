# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# All user sources, that is services from which Keycloak gets user
# information (either by accessing a system like LDAP or integration
# through protocols like OIDC).

resource "keycloak_ldap_user_federation" "ponderoos_ldap" {
  name                    = "ponderoos-ldap"
  realm_id                = keycloak_realm.ponderoos.id
  enabled                 = true
  connection_url          = "ldap://localhost"
  users_dn                = "ou=users,dc=ponderoos,dc=com"
  username_ldap_attribute = "cn"
  uuid_ldap_attribute     = "cn"
  rdn_ldap_attribute      = "cn"
  full_sync_period        = 86400
  trust_email             = true

  user_object_classes = [
    "inetOrgPerson",
    "organizationalPerson",
  ]

  lifecycle {
    # Without this, terraform wants to recreate the resource.
    ignore_changes = [
      delete_default_mappers
    ]
  }
}
