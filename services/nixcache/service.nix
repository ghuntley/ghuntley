# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{
  services.nix-serve = {
    enable = true;
    secretKeyFile = "/var/lib/nix-serve/cache-priv-key.pem";
  };

  services.nginx = {
    enable = true;
    virtualHosts = {
      "nixcache.core.corp.fediversehosting.net" = {
        serverAliases = [ "nixcache" ];
        # TODO(agenix): publish /run/agenix/nix-cache-pub;
        locations."=/cache-key.pub".extraConfig = ''
          alias /run/agenix/nix-cache-pub;
        '';
        locations."/".extraConfig = ''
          proxy_pass http://localhost:${toString config.services.nix-serve.port};
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        '';
      };
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 5000 ];
  };

}
