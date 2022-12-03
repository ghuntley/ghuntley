{ config, lib, pkgs, ... }:

{
  containers.smtp = {
    autoStart = true;
    privateNetwork = true;
    enableTun = true;

    ephemeral = true;

    bindMounts =
      {
        "/var/lib/tailscale" = {
          hostPath = "/srv/smtp/var/lib/tailscale";
          isReadOnly = false;
        };
      };

    config = [ ./service.nix ];

  };


}
