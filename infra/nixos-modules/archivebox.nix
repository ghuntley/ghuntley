# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# NixOS module for ArchiveBox web archiving with backup configuration
{ config, lib, pkgs, ... }:

let
  cfg = config.services.depot.archivebox;
  mkStringOption = default: lib.mkOption {
    inherit default;
    type = lib.types.str;
  };
in
{
  options.services.depot.archivebox = {
    enable = lib.mkEnableOption "ArchiveBox web archiving service";

    domain = mkStringOption "archive.example.com";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Port on which ArchiveBox will listen";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/archivebox";
      description = "Directory where ArchiveBox stores its data";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.archivebox;
      description = "The ArchiveBox package to use";
    };

    createAdmin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to create an admin user during initialization";
    };

    adminUsername = mkStringOption "admin";

    adminEmail = mkStringOption "${config.networking.hostName}@localhost";

    adminPasswordFile = lib.mkOption {
      type = lib.types.path;
      description = "File containing the admin user password";
    };

    # Additional ArchiveBox configuration options
    publicIndex = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to make the index publicly accessible without login";
    };

    publicSnapshots = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to make archived snapshots publicly accessible";
    };

    publicAdd = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to allow public URL submissions without login";
    };

    # Archiving method options
    saveArchiveDotOrg = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Save copies from archive.org";
    };

    saveFavicon = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Save the favicon";
    };

    saveHeaders = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Save HTTP headers";
    };

    saveMercury = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Save Mercury Reader content";
    };

    savePdf = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Save PDF version";
    };

    saveScreenshot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Save screenshot";
    };

    saveSinglefile = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Save SingleFile version";
    };

    saveTitle = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Save page title";
    };

    saveWarc = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Save WARC archive";
    };

    saveWget = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Save wget download";
    };

    saveWgetRequisites = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Save page requisites with wget (CSS, JS, images, etc.)";
    };

    curlUserAgent = lib.mkOption {
      type = lib.types.str;
      default = "Mozilla/5.0 (X11; Fedora; Linux x86_64; rv:135.0) Gecko/20100101 Firefox/135.0";
      description = "User agent string to use for curl requests";
    };

    wgetUserAgent = lib.mkOption {
      type = lib.types.str;
      default = "Mozilla/5.0 (X11; Fedora; Linux x86_64; rv:135.0) Gecko/20100101 Firefox/135.0";
      description = "User agent string to use for wget requests";
    };

    chromeUserAgent = lib.mkOption {
      type = lib.types.str;
      default = "Mozilla/5.0 (X11; Fedora; Linux x86_64; rv:135.0) Gecko/20100101 Firefox/135.0";
      description = "User agent string to use for Chrome/Chromium requests";
    };

    resolution = lib.mkOption {
      type = lib.types.str;
      default = "1440,2000";
      description = "Screenshot resolution in format 'width,height'";
    };

    gitDomains = lib.mkOption {
      type = lib.types.str;
      default = "github.com,bitbucket.org,gitlab.com,gist.github.com,codeberg.org,gitea.com,git.sr.ht,depot.tvl.fyi";
      description = "Comma-separated list of Git hosting domains to attempt Git cloning from";
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional ArchiveBox configuration options";
    };

    insecurePackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "python3.12-django-3.1.14" ];
      description = "List of insecure packages to permit for archivebox";
    };

    enableBackups = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable automatic backups using depot.restic";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure ripgrep is installed
    environment.systemPackages = [
      pkgs.ripgrep
      pkgs.ripgrep-all
      pkgs.youtube-dl
    ];

    # Enable Sonic search backend for full-text search
    services.sonic-server = {
      enable = true;
    };

    systemd.services.archivebox = {
      description = "ArchiveBox web archiving service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = {
        PUBLIC_INDEX = lib.boolToString cfg.publicIndex;
        PUBLIC_SNAPSHOTS = lib.boolToString cfg.publicSnapshots;
        PUBLIC_ADD_VIEW = lib.boolToString cfg.publicAdd;
        SAVE_ARCHIVE_DOT_ORG = lib.boolToString cfg.saveArchiveDotOrg;
        SAVE_FAVICON = lib.boolToString cfg.saveFavicon;
        SAVE_HEADERS = lib.boolToString cfg.saveHeaders;
        SAVE_MERCURY = lib.boolToString cfg.saveMercury;
        SAVE_PDF = lib.boolToString cfg.savePdf;
        SAVE_SCREENSHOT = lib.boolToString cfg.saveScreenshot;
        SAVE_SINGLEFILE = lib.boolToString cfg.saveSinglefile;
        SAVE_TITLE = lib.boolToString cfg.saveTitle;
        SAVE_WARC = lib.boolToString cfg.saveWarc;
        SAVE_WGET = lib.boolToString cfg.saveWget;
        SAVE_WGET_REQUISITES = lib.boolToString cfg.saveWgetRequisites;
        #SEARCH_BACKEND_ENGINE = "sonic"; // TODO: Enable Sonic search backend for full-text search
        SEARCH_BACKEND_ENGINE = "ripgrep";
        CURL_USER_AGENT = cfg.curlUserAgent;
        WGET_USER_AGENT = cfg.wgetUserAgent;
        CHROME_USER_AGENT = cfg.chromeUserAgent;
        RESOLUTION = cfg.resolution;
        GIT_DOMAINS = cfg.gitDomains;
        RIPGREP_BINARY = "${pkgs.ripgrep-all}/bin/rga";
        YOUTUBEDL_BINARY = "${pkgs.youtube-dl}/bin/youtube-dl";
      } // cfg.extraConfig;

      serviceConfig = {
        Type = "simple";
        User = "archivebox";
        Group = "archivebox";
        ExecStart = "${cfg.package}/bin/archivebox server 127.0.0.1:${toString cfg.port}";
        WorkingDirectory = cfg.dataDir;
        StateDirectory = "archivebox";
        StateDirectoryMode = "0750";
        # Add security hardening options
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ cfg.dataDir ];
      };

      preStart = ''
        if [ ! -f ${cfg.dataDir}/index.sqlite3 ]; then
          ${cfg.package}/bin/archivebox init

          ${lib.optionalString cfg.createAdmin ''
            # First create the superuser without password
            ${cfg.package}/bin/archivebox manage createsuperuser \
              --noinput \
              --username ${cfg.adminUsername} \
              --email ${cfg.adminEmail}
          ''}
        fi

        # Set the password using changepassword with a script
        cat > /tmp/set_password.py << EOF
        from django.contrib.auth.models import User
        from django.contrib.auth.hashers import make_password
        with open('${cfg.adminPasswordFile}', 'r') as f:
            password = f.read().strip()
        user = User.objects.get(username='${cfg.adminUsername}')
        user.password = make_password(password)
        user.save()
        EOF

        ${cfg.package}/bin/archivebox manage shell < /tmp/set_password.py
        rm /tmp/set_password.py

        # Write configuration to ArchiveBox.conf
        ${cfg.package}/bin/archivebox config --set PUBLIC_INDEX=${lib.boolToString cfg.publicIndex}
        ${cfg.package}/bin/archivebox config --set PUBLIC_SNAPSHOTS=${lib.boolToString cfg.publicSnapshots}
        ${cfg.package}/bin/archivebox config --set PUBLIC_ADD_VIEW=${lib.boolToString cfg.publicAdd}
        ${cfg.package}/bin/archivebox config --set RIPGREP_BINARY=${pkgs.ripgrep-all}/bin/rga

        ${cfg.package}/bin/archivebox version
        ${cfg.package}/bin/archivebox config --get SEARCH_BACKEND_ENGINE


      '';
    };

    # Create system user and group
    users.users.archivebox = {
      isSystemUser = true;
      group = "archivebox";
      home = cfg.dataDir;
      createHome = true;
    };

    users.groups.archivebox = { };

    # Configure backups using depot.restic
    services.depot.restic = lib.mkIf cfg.enableBackups {
      enable = true;
      paths = [
        cfg.dataDir
        "/var/lib/sonic"
      ];
      exclude = [
        "logs"
        "*.cache"
      ];
    };

    # Configure nginx reverse proxy
    services.nginx.virtualHosts.${cfg.domain} = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;

        extraConfig = ''
          # Security headers
          add_header X-Robots-Tag "none";
          add_header X-Frame-Options "SAMEORIGIN";
          add_header X-Content-Type-Options "nosniff";

          # Larger upload size for archiving
          client_max_body_size 100M;

          # Longer timeouts for archiving operations
          proxy_read_timeout 300;
          proxy_connect_timeout 300;
          proxy_send_timeout 300;
        '';
      };
    };
  };
}
