{ pkgs, config, lib, ... }: {

  services.nginx.virtualHosts."ghuntley.com" = {
    listenAddresses = [ "51.161.196.125" ];
    forceSSL = true;
    enableACME = true;

    locations."/" = {
      extraConfig = ''
        proxy_pass http://localhost:3001;
        proxy_pass_header Authorization;
        proxy_http_version 1.1;
        proxy_ssl_server_name on;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
      '';
    };

    locations."/.well-known/webfinger" = {
      extraConfig = ''
        return 301 https://fediverse.ghuntley.com$request_uri;
      '';
    };

    locations."/linktree/" = {
      extraConfig = ''
        alias /srv/ghuntley.com/static/linktree/;
      '';
    };

    locations."/notes/" = {
      extraConfig = ''
        proxy_pass https://ghuntleynotes.netlify.app;
        proxy_pass_header Authorization;
        proxy_http_version 1.1;
        proxy_ssl_server_name on;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
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
