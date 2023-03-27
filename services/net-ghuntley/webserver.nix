{ pkgs, config, lib, ... }: {

  services.caddy.virtualHosts = {
    "ghuntley.net" = {
      listenAddresses = [ "51.161.196.125" ];
      serverAliases = [ "www.ghuntley.net" ];
      extraConfig = ''
        encode gzip
        root * /srv/ghuntley.net
      '';
    };
  };

}
