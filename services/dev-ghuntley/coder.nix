{ pkgs, config, lib, ... }: {

  services.caddy.virtualHosts = {
    "ghuntley.dev" = {
      listenAddresses = [ "51.161.213.234" ];
      serverAliases = [ "www.ghuntley.dev" "*.ghuntley.dev" ];
      extraConfig = ''
        encode gzip
        reverse_proxy 127.0.0.1:3000
      '';
    };
  };

  virtualisation.oci-containers.containers = {
    coder = {
      extraOptions = [ "--network=host" ];
      image = "ghcr.io/coder/coder:latest";
      user = "coder";
      environmentFiles = [ "/run/agenix/1/ghuntley-dev-coder-secrets" ];
      volumes = [
        "/srv/ghuntley.dev:/home/coder:cached"
        "/var/run/docker.sock:/var/run/docker.sock"
        "/dev/kvm:/dev/kvm"

      ];
      ports = [
        "3000:3000"
      ];
      environment = {
        #CODER_HTTP_ADDRESS = "0.0.0.0:80";
        CODER_ACCESS_URL = "https://ghuntley.dev";
        CODER_DISABLE_PASSWORD_AUTH = "true";
        CODER_EXPERIMENTS = "*";
        CODER_OAUTH2_GITHUB_ALLOW_EVERYONE = "true";
        CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS = "false";
        CODER_OIDC_ALLOW_SIGNUPS = "false";
        CODER_REDIRECT_TO_ACCESS_URL = "false";
        CODER_SECURE_AUTH_COOKIE = "true";
        CODER_SSH_HOSTNAME_PREFIX = "ghuntley-dev";
        CODER_TELEMETRY = "true";
        CODER_UPDATE_CHECK = "true";
        CODER_WILDCARD_ACCESS_URL = "*.ghuntley.dev";
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
