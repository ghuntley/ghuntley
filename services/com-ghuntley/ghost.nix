{ pkgs, config, lib, ... }: {

  services.caddy.enable = true;
  services.caddy.dataDir = "/srv/ghuntley.net";
  services.caddy.email = "ghuntley@ghuntley.com";
  services.caddy.globalConfig = ''
    servers {
        protocols h1 h2 h3
    }
  '';

  services.caddy.virtualHosts = {
    "ghuntley.com" = {
      listenAddresses = [ "51.161.196.125" ];
      serverAliases = [ "www.ghuntley.com" ];
      extraConfig = ''
        encode gzip
        reverse_proxy :3001
      '';
    };
  };

  virtualisation.oci-containers.containers."ghost" = {
    image = "ghost:latest";
    ports = [ "3001:2368" ];
    volumes = [
      "/srv/ghuntley.com/ghost:/var/lib/ghost/content:cached"
    ];
    environment = {
      url = "https://ghuntley.com";
      database__client = "sqlite3";
      database__connection__filename = "/var/lib/ghost/content/data/ghost.db";
      # database__connection__host = "";
      # database__connection__user = "";
      # database__connection__password = "";
      # database__connection__database = "";
    };
  };

  systemd.services.podman-pull-ghost = {
    serviceConfig.User = "root";
    serviceConfig.Type = "oneshot";

    path = [
      pkgs.podman
      pkgs.systemd
    ];

    script = ''
      ${pkgs.podman}/bin/podman pull ghost
      ${pkgs.systemd}/bin/systemctl restart podman-ghost
    '';
  };

  systemd.timers.podman-pull-ghost = {
    wantedBy = [ "timers.target" ];
    partOf = [ "podman-pull-ghost.service" ];
    timerConfig.OnCalendar = "daily";
  };

}
