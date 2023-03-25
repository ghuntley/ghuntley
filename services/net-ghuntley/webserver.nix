{ pkgs, config, lib, ... }: {

  services.nginx.virtualHosts."ghuntley.net" = {
    listenAddresses = [ "51.161.196.125" ];

    forceSSL = true;
    enableACME = true;

    root = "/srv/ghuntley.net";
  };

  services.nginx.virtualHosts."51.161.196.125" = {
    listenAddresses = [ "51.161.196.125" ];

    forceSSL = false;
    enableACME = false;

    root = "/srv/ghuntley.net";
  };

}
