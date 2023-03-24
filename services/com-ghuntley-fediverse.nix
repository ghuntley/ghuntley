{
  services.nginx.virtualHosts."fediverse.ghuntley.com" = {
    forceSSL = true;
    enableACME = true;

    root = "${config.services.mastodon.package}/public/";

    locations."/system/".alias = "/var/lib/mastodon/public-system/";

    locations."/" = {
      tryFiles = "$uri @proxy";
    };

    locations."@proxy" = {
      proxyPass = (if config.services.mastodon.enableUnixSocket then "http://unix:/run/mastodon-web/web.socket" else "http://127.0.0.1:${toString(config.services.mastodon.webPort)}");
      proxyWebsockets = true;
    };

    locations."/api/v1/streaming/" = {
      proxyPass = (if config.services.mastodon.enableUnixSocket then "http://unix:/run/mastodon-streaming/streaming.socket" else "http://127.0.0.1:${toString(config.services.mastodon.streamingPort)}/");
      proxyWebsockets = true;
    };
  };

  #
  # https://docs.joinmastodon.org/admin/config/
  #
  services.elasticsearch.enable = true;
  services.elasticsearch.package = pkgs.elasticsearch7;
  services.mastodon.elasticsearch.host = "localhost";


  services.mastodon.enable = true;
  services.mastodon.enableUnixSocket = false;
  services.mastodon.configureNginx = false;
  services.mastodon.localDomain = "ghuntley.com";
  services.mastodon.extraConfig = {
    #    ALTERNATE_DOMAINS = "ghuntley.social";
    WEB_DOMAIN = "fediverse.ghuntley.com";

    SINGLE_USER_MODE = "true";
    EMAIL_DOMAIN_ALLOWLIST = "ghuntley.com";

    #RAILS_LOG_LEVEL = "debug";
  };

  services.mastodon.smtp.fromAddress = "mastodon@fediverse.ghuntley.com";

  #services.mastodon.smtp.authenticate = true;
  #services.mastodon.smtp.user = "postmaster@mg.ghuntley.com";
  #services.mastodon.smtp.host = "smtp.mailgun.org";
  #services.mastodon.smtp.port = 465;
}
