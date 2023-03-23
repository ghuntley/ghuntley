# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Redirect the hostname of a machine to its configuration in a web
# browser.
#
# Works by convention, assuming that the machine has its configuration
# at //ops/machines/${hostname}.
{ config, ... }:

let
  host = "${config.networking.hostName}.${config.networking.domain}";
in
{
  imports = [
    ./default.nix
  ];

  # config.services.nginx.virtualHosts."${host}" = {
  #   serverName = host;
  #   addSSL = true; # SSL is not forced on these redirects
  #   enableACME = true;

  #   extraConfig = ''
  #     location = / {
  #       return 302 https://sourcegraph.com/search?q=context:global+repo:ghuntley/depot+${config.networking.hostName};
  #     }
  #   '';
  # };
}
