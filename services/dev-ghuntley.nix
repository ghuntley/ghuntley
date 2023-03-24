# security.acme.acceptTerms = true;
# security.acme.email = "ghuntley@ghuntley.com";
# security.acme.defaults.dnsProvider = "cloudflare";
# security.acme.defaults.credentialsFile = "/etc/cloudflare-api-token";
# security.acme.defaults.enableDebugLogs = true;
# security.acme.certs."ghuntley.dev".credentialsFile = "/etc/cloudflare-api-token";
# security.acme.certs."ghuntley.dev".extraDomainNames = [ "*.ghuntley.dev"];

{
  services.postgresql.package = pkgs.postgresql_13;

  virtualisation.oci-containers.containers."coder" = {
    extraOptions = [ "--network=host" ];
    image = "ghcr.io/coder/coder:latest";
    user = "root";
    volumes = [
      "/srv/ghuntley.dev:/home/coder:cached"
      "/var/run/docker.sock:/var/run/docker.sock"
    ];
    environment = {
      CODER_ACCESS_URL = "https://ghuntley.dev";
      CODER_WILDCARD_ACCESS_URL = "*.ghuntley.dev";
      CODER_HTTP_ADDRESS = "0.0.0.0:3000";
      CODER_PG_CONNECTION_URL = "postgres://coder:redacted@127.0.0.1/coder?sslmode=disable";

      CODER_TELEMETRY = "true";

      CODER_EXPERIMENTS = "*";

      CODER_OIDC_ALLOW_SIGNUPS = "false";
      CODER_DISABLE_PASSWORD_AUTH = "true";
      CODER_SECURE_AUTH_COOKIE = "true";
      #CODER_REDIRECT_TO_ACCESS_URL="true";

      CODER_OAUTH2_GITHUB_ALLOW_EVERYONE = "true";
      CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS = "false";
      CODER_OAUTH2_GITHUB_CLIENT_ID = "redacted";
      CODER_OAUTH2_GITHUB_CLIENT_SECRET = "redacted";

      CODER_GITAUTH_0_ID = "github";
      CODER_GITAUTH_0_TYPE = "github";
      CODER_GITAUTH_0_CLIENT_ID = "redacted";
      CODER_GITAUTH_0_CLIENT_SECRET = "redacted";

      GOOGLE_APPLICATION_CREDENTIALS = "/home/coder/gcp-ghuntley-dev.json";
    };

    systemd.services.docker-pull-coder = {
      serviceConfig.User = "root";
      serviceConfig.Type = "oneshot";

      path = [
        pkgs.docker
        pkgs.systemd
      ];

      script = ''
        ${pkgs.docker}/bin/docker pull ghcr.io/coder/coder
        ${pkgs.systemd}/bin/systemctl restart docker-coder
      '';
    };

    systemd.timers.docker-pull-coder = {
      wantedBy = [ "timers.target" ];
      partOf = [ "updateghost.service" ];
      timerConfig.OnCalendar = "daily";
    };
  }
