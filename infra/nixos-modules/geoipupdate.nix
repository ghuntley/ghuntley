# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# NixOS module for Open WebUI - a web interface for interacting with large language models
{ depot, pkgs, config, lib, ... }:

let
  inherit (builtins) attrValues mapAttrs;
  inherit (lib)
    concatStringsSep
    mkEnableOption
    mkIf
    mkOption
    types;

  cfg = config.services.depot.geoipupdate;
  description = "MaxMind GeoIP Update";

  # Helper functions for argument preparation
  prepareArgs = args:
    concatStringsSep " "
      (attrValues (mapAttrs (key: value: "-${key} \"${toString value}\"")
        args));
in
{
  options.services.depot.geoipupdate = {
    enable = mkEnableOption description;

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/GeoIP";
      description = "Directory where GeoIPUpdate stores its data";
    };

    accountId = mkOption {
      type = types.int;
      description = "MaxMind Account ID";
      example = "1234567890";
    };

    licenseKey = mkOption {
      type = types.path;
      description = "MaxMind License Key";
      example = "config.age.secrets.geoipupdate-license-key.path";
    };
  };

  config = mkIf cfg.enable {
    services.geoipupdate = {
      enable = true;
      settings = {
        AccountID = cfg.accountId;
        LicenseKey = cfg.licenseKey;
        EditionIDs = [
          "GeoLite2-ASN"
          "GeoLite2-City"
          "GeoLite2-Country"
        ];
        DatabaseDirectory = cfg.stateDir;
      };
    };
  };
}
