# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, ... }:

{
  imports = [
    ./default.nix
  ];

  config = {
    services.nginx.virtualHosts."21kbh.com" = {
      serverName = "21kbh.com";
      root = depot.web.tvl;
      enableACME = true;
      forceSSL = true;

      extraConfig = ''
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

        rewrite ^/builds/?$ https://buildkite.com/21kbh/depot/ last;

      '';
    };
  };
}
