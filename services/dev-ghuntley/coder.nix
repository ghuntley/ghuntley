{ pkgs, config, lib, ... }: {

  virtualisation.oci-containers.containers = {
    coder = {
      # extraOptions = [ "--network=host" ];
      image = "ghcr.io/coder/coder:latest";
      user = "coder";
      volumes = [
        "/srv/ghuntley.dev:/home/coder:cached"
        "/var/run/docker.sock:/var/run/docker.sock"
      ];
      ports = [
        "3000:3000"
      ];
      environment = {
        #CODER_REDIRECT_TO_ACCESS_URL="true";
        # CODER_ACCESS_URL = "https://ghuntley.dev";
        # CODER_DISABLE_PASSWORD_AUTH = "false";
        # CODER_EXPERIMENTS = "*";
        # CODER_GITAUTH_0_CLIENT_ID = "cat /home/coder/coder-gitauth-0-client-id";
        # CODER_GITAUTH_0_CLIENT_SECRET = "cat /home/coder/coder-gitauth-0-client-secret";
        # CODER_GITAUTH_0_ID = "github";
        # CODER_GITAUTH_0_TYPE = "github";
        # CODER_HTTP_ADDRESS = "0.0.0.0:80";
        # CODER_OAUTH2_GITHUB_ALLOW_EVERYONE = "true";
        # CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS = "true";
        # CODER_OAUTH2_GITHUB_CLIENT_ID = "cat /home/coder/coder-oauth2-github-client-id";
        # CODER_OAUTH2_GITHUB_CLIENT_SECRET = "cat /home/coder/coder-oauth2-github-client-secret";
        # CODER_OIDC_ALLOW_SIGNUPS = "true";
        # # CODER_PG_CONNECTION_URL = "cat /home/coder/coder-postgresql-conection-string";
        # CODER_SECURE_AUTH_COOKIE = "true";
        # CODER_SSH_HOSTNAME_PREFIX = "ghuntley-dev";
        # CODER_TELEMETRY = "true";
        # CODER_TLS_ADDRESS = "0.0.0.0:443";
        # CODER_TLS_CERT_FILE = "";
        # CODER_TLS_ENABLE = "false";
        # CODER_TLS_KEY_FILE = "";
        # CODER_UPDATE_CHECK = "true";
        # CODER_WILDCARD_ACCESS_URL = "*.ghuntley.dev";

        GOOGLE_APPLICATION_CREDENTIALS = "/home/coder/coder-gcp-service-account-ghuntley-dev-token";
      };
    };
  };

  systemd.services.podman-pull-coder = {
    serviceConfig.User = "root";
    serviceConfig.Type = "oneshot";

    path = [
      pkgs.podman
      pkgs.systemd
    ];

    script = ''
      ${pkgs.podman}/bin/podman pull "ghcr.io/coder/coder:latest"
      ${pkgs.systemd}/bin/systemctl restart podman-coder
    '';
  };

  systemd.timers.podman-pull-coder = {
    wantedBy = [ "timers.target" ];
    partOf = [ "podman-pull-coder.service" ];
    timerConfig.OnCalendar = "daily";
  };
}
