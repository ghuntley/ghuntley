# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

# Configuration for running the Overalls cgit instance using thttpd.
{ config, depot, lib, pkgs, ... }:

let
  cfg = config.services.depot.cgit;

  userConfig =
    if builtins.isNull cfg.user then {
      DynamicUser = true;
    } else {
      User = cfg.user;
      Group = cfg.user;
    };
in
{
  options.services.depot.cgit = with lib; {
    enable = mkEnableOption "Run cgit web interface for depot";

    port = mkOption {
      description = "Port on which cgit should listen";
      type = types.int;
      default = 2448;
    };

    repo = mkOption {
      description = "Path to depot's .git folder on the machine";
      type = types.str;
      default = "/var/lib/gerrit/git/depot.git/";
    };

    user = mkOption {
      description = ''
        User to use for the cgit service. It is expected that this is
        also the name of the user's primary group.
      '';

      type = with types; nullOr str;
      default = null;
    };
  };

  config = lib.mkIf cfg.enable {

    services.nginx.virtualHosts.cgit = {
      serverName = "code.ponderoos.com";
      enableACME = true;
      forceSSL = true;

      extraConfig = ''
        # Serve the rendered Tvix component SVG.
        #
        # TODO(tazjin): Implement a way of serving this dynamically
        # location = /about/tvix/docs/component-flow.svg {
        #     alias $depot.tvix.docs.svg}/component-flow.svg;
        # }

        # Git operations on depot.git hit josh
        location /depot.git {
            proxy_pass http://localhost:${toString config.services.depot.josh.port};
        }

        # Git clone operations on '/' should be redirected to josh now.
        location = /info/refs {
            return 302 https://code.ponderoos.com/depot.git/info/refs$is_args$args;
        }

        # Static assets must always hit the root.
        location ~ ^/(favicon\.ico|cgit\.(css|png))$ {
          proxy_pass http://localhost:2448;
        }

        # Everything else is forwarded to cgit for the web view
        location / {
            proxy_pass http://localhost:2448/cgit.cgi/depot/;
        }
      '';
    };


    systemd.services.cgit = {
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Restart = "on-failure";

        ExecStart = depot.infra.scm.cgit-ponderoos.override {
          inherit (cfg) port repo;
        };
      } // userConfig;
    };
  };
}
