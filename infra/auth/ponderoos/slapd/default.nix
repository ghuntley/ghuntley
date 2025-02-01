# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

# Configures an OpenLDAP instance for Ponderoos
#
# TODO(tazjin): Configure ldaps://
{ depot, lib, pkgs, ... }:

with depot.nix.yants;

let
  user = struct {
    username = string;
    email = string;
    password = string;
    displayName = option string;
  };

  toLdif = defun [ user string ] (u: ''
    dn: cn=${u.username},ou=users,dc=ponderoos,dc=com
    objectClass: organizationalPerson
    objectClass: inetOrgPerson
    sn: ${u.username}
    cn: ${u.username}
    displayName: ${u.displayName or u.username}
    mail: ${u.email}
    userPassword: ${u.password}
  '');

  inherit (depot.infra.auth.ponderoos) users;

in
{
  services.openldap = {
    enable = true;

    settings.children = {
      "olcDatabase={1}mdb".attrs = {
        objectClass = [ "olcDatabaseConfig" "olcMdbConfig" ];
        olcDatabase = "{1}mdb";
        olcDbDirectory = "/var/lib/openldap/db";
        olcSuffix = "dc=ponderoos,dc=com";
        olcAccess = "to *  by * read";
        olcRootDN = "cn=admin,dc=ponderoos,dc=com";
        olcRootPW = "{ARGON2}$argon2id$v=19$m=19456,t=2,p=1$2uZ9rEykyFf14fnNT2rTdQ$CwP44MeRzkzsAa68LePq4Fxs8PnuvtfA4PJilT/fMn4";
      };

      "cn=module{0}".attrs = {
        objectClass = "olcModuleList";
        olcModuleLoad = "argon2";
      };

      "cn=schema".includes =
        map (schema: "${pkgs.openldap}/etc/schema/${schema}.ldif")
          [ "core" "cosine" "inetorgperson" "nis" ];
    };

    # Contents are immutable at runtime, and adding user accounts etc.
    # is done statically in the LDIF-formatted contents in this folder.
    declarativeContents."dc=ponderoos,dc=com" = ''
      dn: dc=ponderoos,dc=com
      dc: ponderoos
      o: Ponderoos LDAP server
      description: Root entry for ponderoos.com
      objectClass: top
      objectClass: dcObject
      objectClass: organization

      dn: ou=users,dc=ponderoos,dc=com
      ou: users
      description: All users in Ponderoos
      objectClass: top
      objectClass: organizationalUnit

      dn: ou=groups,dc=ponderoos,dc=com
      ou: groups
      description: All groups in Ponderoos
      objectClass: top
      objectClass: organizationalUnit

      ${lib.concatStringsSep "\n" (map toLdif users)}
    '';
  };

  services.depot.restic = {
    paths = [ "/var/lib/openldap/db" ];
    exclude = [ "" ];
  };

}
