{ config, lib, pkgs, ... }:

{
  containers.time = {
    autoStart = true;
    privateNetwork = true;
    enableTun = true;

    ephemeral = true;

    bindMounts =
      {
        "/var/lib/tailscale" = {
          hostPath = "/srv/time/var/lib/tailscale";
          isReadOnly = false;
        };
      };

    config = [ ./service.nix ];

  };


}
