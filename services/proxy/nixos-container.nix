{ config, lib, pkgs, ... }:

{
  containers.proxy = {
    autoStart = true;
    privateNetwork = true;
    enableTun = true;

    ephemeral = true;

    bindMounts =
      {
        "/var/lib/tailscale" = {
          hostPath = "/srv/proxy/var/lib/tailscale";
          isReadOnly = false;
        };
        "/var/cache/squid" = {
          hostPath = "/srv/proxy/var/cache/squid";
          isReadOnly = false;
        };
        "/var/log/squid" = {
          hostPath = "/srv/proxy/var/log/squid";
          isReadOnly = false;
        };
      };

    config = [ ./service.nix ];

  };


}
