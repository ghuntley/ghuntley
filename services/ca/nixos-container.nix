{ config, lib, pkgs, ... }:

{
  containers.ca = {
    autoStart = true;
    privateNetwork = true;
    enableTun = true;

    ephemeral = true;

    bindMounts =
      {
        "/var/lib/tailscale" = {
          hostPath = "/srv/ca/var/lib/tailscale";
          isReadOnly = false;
        };
        "/var/lib/cfssl" = {
          hostPath = "/srv/ca/var/lib/cfssl";
          isReadOnly = false;
        };
      };

    config = [ ./service.nix ];

  };


}
