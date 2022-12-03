{ config, lib, pkgs, ... }:

{
  containers.nixcache = {
    autoStart = true;
    privateNetwork = true;
    enableTun = true;

    ephemeral = true;

    bindMounts =
      {
        "/var/lib/tailscale" = {
          hostPath = "/srv/binarycache/var/lib/tailscale";
          isReadOnly = false;
        };
        "/var/lib/nix-serve" = {
          hostPath = "/srv/binarycache/var/lib/nix-serve";
          isReadOnly = false;
        };
        "/nix" = {
          hostPath = "/nix";
          isReadOnly = false;
        };
      };

    config = [ ./nixos-container.nix ];

  };


}
