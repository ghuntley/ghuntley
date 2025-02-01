# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Configures the public josh instance for serving the depot.
{ config, depot, lib, pkgs, ... }:

let
  cfg = config.services.depot.wastebin;
in
{
  options.services.depot.wastebin = with lib; {
    enable = mkEnableOption "Enable wastebin for serving pastes";

    port = mkOption {
      description = "Port on which wastebin should listen";
      type = types.int;
      default = 3751;
    };
  };

  config = lib.mkIf cfg.enable {

    services.wastebin = {
      enable = true;
      secretFile = config.age.secrets.wastebin-secret-file.path;
      stateDir = "/var/lib/wastebin";
      settings = {
        WASTEBIN_TITLE = "Clip";
        WASTEBIN_DATABASE_PATH = "/var/lib/wastebin/sqlite3.db";
        WASTEBIN_BASE_URL = "https://clip.ponderoos.com";
        WASTEBIN_ADDRESS_PORT = "127.0.0.1:${toString config.services.depot.wastebin.port}";
      };
    };

    services.depot.restic = {
      paths = [ "/var/lib/wastebin" ];
      exclude = [ ];
    };

    services.nginx.virtualHosts."clip.ponderoos.com" = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.depot.wastebin.port}";

        extraConfig = ''
          add_header X-Robots-Tag "none";
        '';
      };
    };
  };

}
