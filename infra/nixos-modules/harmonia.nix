# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, config, lib, pkgs, ... }:

let
  cfg = config.services.depot.harmonia;
  description = "Harmonia: Nix binary cache written in Rust";
in
{
  options.services.depot.harmonia = {
    enable = lib.mkEnableOption description;

    signKeyPath = lib.mkOption {
      type = lib.types.str;
      example = "config.age.secrets.nix-cache-signkey.path";
      description = "Path to the signing keys to use for signing the cache";
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      example = "nix-cache.ponderoos.com";
      description = "The hostname part of the public URL used as base for all frontend requests.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.harmonia = {
      enable = true;
      signKeyPaths = [ cfg.signKeyPath ];
    };

    # Override the systemd service to add RUST_LOG
    systemd.services.harmonia.environment = {
      RUST_LOG = "debug,actix_web::middleware=debug";
    };

    services.nginx = {
      virtualHosts."${cfg.hostname}" = {
        enableACME = true;
        forceSSL = true;

        locations."/".extraConfig = ''
          proxy_pass http://127.0.0.1:5000;
          proxy_set_header Host $host;
          proxy_redirect http:// https://;
          proxy_http_version 1.1;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;

          # Increase timeouts for large files
          proxy_connect_timeout 300s;
          proxy_send_timeout 300s;
          proxy_read_timeout 300s;

          # Increase buffer sizes
          proxy_buffer_size 16k;
          proxy_buffers 8 16k;
          proxy_busy_buffers_size 32k;

          # Increase max temp file sizes for very large files (up to 64GB)
          proxy_max_temp_file_size 65536m;
          proxy_temp_file_write_size 64k;

          add_header X-Robots-Tag "none";
        '';
      };
    };
  };
}
