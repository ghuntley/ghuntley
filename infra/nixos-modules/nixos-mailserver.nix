# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, depot, lib, ... }:

let
  cfg = config.services.depot.mailserver;
  description = "Simple NixOS Mailserver";
in
{
  imports = [
    depot.third_party.nixos-mailserver
  ];

  options.services.depot.mail = {
    enable = lib.mkEnableOption description;

    fqdn = lib.mkOption {
      type = lib.types.str;
      example = "mail.ponderoos.com";
      description = "The FQDN of the mailserver.";
    };

    domains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [ "ponderoos.com" ];
      description = "A list of domains to configure for the mailserver.";
    };

    sendingFqdn = lib.mkOption {
      type = lib.types.str;
      example = "ponderoos.com";
      description = "The FQDN of the sending mailserver.";
    };

    certificateDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [ "imap.ponderoos.com" "pop3.ponderoos.com" ];
      description = "A list of domains to configure for the mailserver.";
    };


    loginAccounts = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      example = {
        "hello@ponderoos.com" = {
          hashedPasswordFile = config.age.secrets.inbox-hello-credentials.path;
        };
      };
      description = "A list of login accounts to configure for the mailserver. To create the password hashes, use nix-shell -p mkpasswd --run 'mkpasswd -sm bcrypt'";
    };

    organizationName = lib.mkOption {
      type = lib.types.str;
      example = "Ponderoos";
      description = "The name of the organization.";
    };
  };

  config = lib.mkIf cfg.enable {

    mailserver = {
      enable = true;
      fqdn = cfg.fqdn;
      domains = cfg.domains;
      certificateDomains = cfg.certificateDomains;
      sendingFqdn = cfg.sendingFqdn;

      rewriteMessageId = true;

      loginAccounts = cfg.loginAccounts;

      dmarcReporting = {
        enable = true;
        domain = cfg.sendingFqdn;
        organizationName = cfg.organizationName;
      };

      enableManageSieve = true;

      virusScanning = true;

      fullTextSearch = {
        enable = true;
        # index new email as they arrive
        autoIndex = true;
        enforced = "body";
      };

      # Use Let's Encrypt certificates. Note that this needs to set up a stripped
      # down nginx and opens port 80.
      certificateScheme = "acme-nginx";
    };


    services.depot.restic.paths = [
      "/var/vmail"
      "/var/sieve"
      "/var/dkim"
    ];

    services.roundcube = {
      enable = true;
      hostName = cfg.fqdn;
      extraConfig = ''
        # starttls needed for authentication, so the fqdn required to match
        # the certificate
        $config['smtp_server'] = "tls://${cfg.fqdn}";
        $config['smtp_user'] = "%u";
        $config['smtp_pass'] = "%p";
      '';
    };

    services.postgresqlBackup = {
      databases = [
        "roundcube"
      ];
    };


  };
}
