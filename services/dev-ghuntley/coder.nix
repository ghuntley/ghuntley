{ pkgs, config, lib, ... }: {

  services.postgresql.package = pkgs.postgresql_13;
  services.postgresql.ensureDatabases = [ "coder" ];
  services.postgresql.enable = true;

  services.postgresqlBackup.enable = true;
  services.postgresqlBackup.databases = [ "coder" ];
  services.postgresqlBackup.location = "/var/lib/postgresql/backups";

  networking.hosts = {
    "104.21.87.102" = [ "ghuntley.com ghuntley.net ghuntley.dev" ];
  };

  security.acme.acceptTerms = true;
  security.acme.defaults.email = "ghuntley@ghuntley.com";

  services.nginx = {
    enable = true;

    # Use recommended settings
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    # Only allow PFS-enabled ciphers with AES256
    sslCiphers = "AES256+EECDH:AES256+EDH:!aNULL";

    commonHttpConfig = ''
      # Add HSTS header with preloading to HTTPS requests.
      # Adding this header to HTTP requests is discouraged
      map $scheme $hsts_header {
          https   "max-age=31536000; includeSubdomains; preload";
      }
      add_header Strict-Transport-Security $hsts_header;

      # Enable CSP for your services.
      #add_header Content-Security-Policy "script-src 'self'; object-src 'none'; base-uri 'none';" always;

      # Minimize information leaked to other domains
      add_header 'Referrer-Policy' 'origin-when-cross-origin';

      # Disable embedding as a frame
      add_header X-Frame-Options DENY;

      # Prevent injection of code in other mime types (XSS Attacks)
      add_header X-Content-Type-Options nosniff;

      # Enable XSS protection of the browser.
      # May be unnecessary when CSP is configured properly (see above)
      add_header X-XSS-Protection "1; mode=block";

      # This might create errors
      proxy_cookie_path / "/; secure; HttpOnly; SameSite=strict";
    '';
  };

  services.nginx.virtualHosts."ghuntley.net" = {
    forceSSL = false;
    enableACME = true;

    root = "/srv/ghuntley.net";
  };

  services.nginx.virtualHosts."ghuntley.dev" = {

    #serverAliases = ["*.ghuntley.dev"];

    #sslCertificateKey = "/var/lib/acme/ghuntley.dev/key.pem";
    #sslCertificate = "/var/lib/acme/ghuntley.dev/fullchain.pem";

    forceSSL = false;
    enableACME = true;

    locations."/" = {
      extraConfig = ''
        proxy_pass http://localhost:3000;
        proxy_pass_header Authorization;
        proxy_http_version 1.1;
        proxy_ssl_server_name on;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $host;
      '';
    };

    #    locations."/bin" = {
    #      extraConfig = ''
    #        proxy_pass https://dev.coder.com/bin;
    #        proxy_pass_header Authorization;
    #        proxy_http_version 1.1;
    #        proxy_ssl_server_name on;
    #        proxy_set_header Upgrade $http_upgrade;
    #        proxy_set_header Connection "upgrade";
    #        proxy_set_header X-Real-IP $remote_addr;
    #        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    #        proxy_set_header X-Forwarded-Proto $scheme;
    #        proxy_buffering off;
    #      '';
    #    };
  };



  services.nginx.virtualHosts."ghuntley.com" = {

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


  # services.caddy.virtualHosts = {
  #   "ghuntley.dev" = {
  #     serverAliases = [ "www.ghuntley.dev" "*.ghuntley.dev" ];
  #     extraConfig = ''
  #       encode gzip
  #       reverse_proxy :3000
  #     '';
  #   };
  # };

  virtualisation.oci-containers.containers = {
    coder = {
      extraOptions = [ "--network=host" ];
      image = "ghcr.io/coder/coder:latest";
      user = "root";
      environmentFiles = [ config.age.secrets.ghuntley-dev-coder-secrets.path ];
      volumes = [
        "/srv/ghuntley.dev:/home/coder:cached"
        "/var/run/docker.sock:/var/run/docker.sock"
        "/var/run/libvirt/libvirt-sock:/var/run/libvirt/libvirt-sock"
        "/var/lib/libvirt/images:/var/lib/libvirt/images"
        "/dev/kvm:/dev/kvm"
      ];
      ports = [
        "3000:3000"
      ];

      environment = {
        #CODER_HTTP_ADDRESS = "0.0.0.0:3000";
        CODER_ACCESS_URL = "https://ghuntley.dev";
        CODER_DISABLE_PASSWORD_AUTH = "true";
        CODER_EXPERIMENTS = "*";
        CODER_OAUTH2_GITHUB_ALLOW_EVERYONE = "true";
        CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS = "false";
        CODER_OIDC_ALLOW_SIGNUPS = "false";
        CODER_REDIRECT_TO_ACCESS_URL = "false";
        CODER_SECURE_AUTH_COOKIE = "true";
        # CODER_SSH_HOSTNAME_PREFIX = "ghuntley-dev";
        CODER_VERBOSE = "true";
        CODER_TELEMETRY = "true";
        CODER_UPDATE_CHECK = "true";
        CODER_WILDCARD_ACCESS_URL = "*.ghuntley.dev";

        GOOGLE_APPLICATION_CREDENTIALS = "/home/coder/coder-gcp-service-account-ghuntley-dev-token";
        CODER_PG_CONNECTION_URL = "postgres://coder:coder@localhost/coder?sslmode=disable";
        TF_LOG = "DEBUG";
      };
    };
  };

  systemd.services.docker-pull-coder = {
    serviceConfig.User = "root";
    serviceConfig.Type = "oneshot";

    path = [
      pkgs.docker
      pkgs.systemd
    ];

    script = ''
      ${pkgs.docker}/bin/docker pull "ghcr.io/coder/coder:latest"
      ${pkgs.systemd}/bin/systemctl restart docker-coder

      # wait for coder container to start before adding cdrkit
      sleep 5
      ${pkgs.docker}/bin/docker exec `docker ps -aqf "name=^coder$"` apk add cdrkit
    '';
  };

  systemd.timers.docker-pull-coder = {
    wantedBy = [ "timers.target" ];
    partOf = [ "docker-pull-coder.service" ];
    timerConfig.OnCalendar = "daily";
  };
}
