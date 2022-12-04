# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

# Run sourcegraph, including its entire machinery, in a container.
# Running it outside of a container is a futile endeavour for now.
{ depot, config, pkgs, lib, ... }:

let
  cfg = config.services.depot.sourcegraph;
in
{
  options.services.depot.sourcegraph = with lib; {
    enable = mkEnableOption "SourceGraph code search engine";

    port = mkOption {
      description = "Port on which SourceGraph should listen";
      type = types.int;
      default = 3463;
    };

    cheddarPort = mkOption {
      description = "Port on which cheddar should listen";
      type = types.int;
      default = 4238;
    };
  };

  config = lib.mkIf cfg.enable {
    # Run a cheddar syntax highlighting server
    systemd.services.cheddar-server = {
      wantedBy = [ "multi-user.target" ];
      script = "${depot.tools.cheddar}/bin/cheddar --listen 0.0.0.0:${toString cfg.cheddarPort} --sourcegraph-server";

      serviceConfig = {
        DynamicUser = true;
        Restart = "always";
      };
    };

    # TODO(security): migrate to depot-src instead of docker image to ensure this is updated automatically
    virtualisation.oci-containers.containers.sourcegraph = {
      image = "sourcegraph/server:4.2.0";

      ports = [
        "127.0.0.1:${toString cfg.port}:7080"
      ];

      volumes = [
        "/var/lib/sourcegraph/etc:/etc/sourcegraph"
        "/var/lib/sourcegraph/data:/var/opt/sourcegraph"
      ];

      # TODO(tazjin): Figure out what changed in the protocol.
      # environment.SRC_SYNTECT_SERVER = "http://172.17.0.1:${toString cfg.cheddarPort}";

      # Sourcegraph needs a higher nofile limit, it logs warnings
      # otherwise (unclear whether it actually affects the service).
      extraOptions = [
        "--ulimit"
        "nofile=10000:10000"
      ];
    };
  };
}
