# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

# NixOS module for configuring the simple SMTP relay.
{ depot, pkgs, config, lib, ... }:

let
  inherit (builtins) attrValues mapAttrs;
  inherit (lib)
    concatStringsSep
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.services.depot.smtprelay;
  description = "Simple SMTP relay";

  # Configuration values that are always overridden.
  #
  # - logging is pinned to stdout for journald compatibility
  # - secret config is loaded through systemd's credential loading facility
  overrideArgs = {
    logfile = "";
    log_format = "json";
    config = "$CREDENTIALS_DIRECTORY/secrets";
  };

  # Creates the command line argument string for the service.
  prepareArgs = args:
    concatStringsSep " "
      (attrValues (mapAttrs (key: value: "-${key} \"${toString value}\"")
        (args // overrideArgs)));
in
{
  options.services.depot.smtprelay = {
    enable = mkEnableOption description;

    args = mkOption {
      type = types.attrsOf types.str;
      description = "Key value pairs for command line arguments";
    };

    secretsFile = mkOption {
      type = types.str;
      default = config.age.secretsDir + "/smtprelay-config";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.smtprelay = {
      inherit description;
      script = "${depot.third_party.smtprelay}/bin/smtprelay ${prepareArgs cfg.args}";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Restart = "always";
        StateDirectory = "smtprelay";
        DynamicUser = true;
        LoadCredential = "secrets:${cfg.secretsFile}";
      };
    };
  };
}
