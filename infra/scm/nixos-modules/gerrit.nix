# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT


# Gerrit configuration for the TVL monorepo
{ depot, pkgs, config, lib, ... }:

let
  cfg = config.services.gerrit;

  besadiiWithConfig = name: pkgs.writeShellScript "besadii-whitby" ''
    export BESADII_CONFIG=/run/agenix/gerrit-besadii-config
    exec -a ${name} ${depot.infra.scm.besadii}/bin/besadii "$@"
  '';

  gerritHooks = pkgs.runCommand "gerrit-hooks" { } ''
    mkdir -p $out
    ln -s ${besadiiWithConfig "change-merged"} $out/change-merged
    ln -s ${besadiiWithConfig "patchset-created"} $out/patchset-created
  '';
in
{

  services.gerrit = {
    enable = true;
    listenAddress = "[::]:4778"; # 4778 - grrt
    serverId = "27d2efe1-0d79-4249-b692-89a098f35a7d"; # nix-shell -p util-linux --run uuidgen

    builtinPlugins = [
      "codemirror-editor"
      "download-commands"
      "hooks"
      "delete-project"
      "replication"
    ];

    plugins = with depot.third_party.gerrit_plugins; [
      code-owners
      oauth
      depot.infra.scm.gerrit-ponderoos
    ];

    package = depot.third_party.gerrit;

    jvmHeapLimit = "4g";

    jvmPackage = pkgs.jdk21_headless;

    settings = {
      core.packedGitLimit = "100m";
      log.jsonLogging = true;
      log.textLogging = false;
      sshd.advertisedAddress = "code.ponderoos.com:29418";
      # hooks.path = "${gerritHooks}";
      cache.web_sessions.maxAge = "3 months";
      plugins.allowRemoteAdmin = false;
      change.enableAttentionSet = true;
      change.enableAssignee = false;

      # Configures gerrit for being reverse-proxied by nginx as per
      # https://gerrit-review.googlesource.com/Documentation/config-reverseproxy.html
      gerrit = {
        canonicalWebUrl = "https://cl.ponderoos.com";
        docUrl = "/Documentation";
      };

      httpd.listenUrl = "proxy-https://${cfg.listenAddress}";

      download.command = [
        "checkout"
        "cherry_pick"
        "format_patch"
        "pull"
      ];

      # Configure for cgit.
      gitweb = {
        type = "custom";
        url = "https://code.ponderoos.com";
        project = "/";
        revision = "/commit/?id=\${commit}";
        branch = "/log/?h=\${branch}";
        tag = "/tag/?h=\${tag}";
        roottree = "/tree/?h=\${commit}";
        file = "/tree/\${file}?h=\${commit}";
        filehistory = "/log/\${file}?h=\${branch}";
        linkname = "cgit";
      };

      # Auto-link panettone bug links
      commentlink.panettone = {
        match = "b/(\\d+)";
        link = "https://b.ponderoos.com/issues/$1";
      };

      # Auto-link other CLs
      commentlink.gerrit = {
        match = "cl/(\\d+)";
        link = "https://cl.ponderoos.com/$1";
      };

      # Auto-link links to monotonically increasing revisions/commits
      commentlink.revision = {
        match = "r/(\\d+)";
        link = "https://code.ponderoos.com/commit/?h=refs/r/$1";
      };

      # Configures integration with Keycloak, which then integrates with a
      # variety of backends.
      auth.type = "OAUTH";
      plugin.gerrit-oauth-provider-keycloak-oauth = {
        root-url = "https://auth.ponderoos.com/auth";
        realm = "Ponderoos";
        client-id = "gerrit";
        # client-secret is set in /var/lib/gerrit/etc/secure.config.
        # [plugin "gerrit-oauth-provider-keycloak-oauth"]
        # client-secret = "redacted"

      };

      plugin.code-owners = {
        # A Code-Review +2 vote is required from a code owner.
        requiredApproval = "Code-Review+2";
        # The OWNERS check can be overriden using an Owners-Override vote.
        overrideApproval = "Owners-Override+1";
        # People implicitly approve their own changes automatically.
        enableImplicitApprovals = "TRUE";
      };

      # Allow users to add additional email addresses to their accounts.
      oauth.allowRegisterNewEmail = true;

      # Use Gerrit's built-in HTTP passwords, rather than trying to use the
      # password against the backing OAuth provider.
      auth.gitBasicAuthPolicy = "HTTP";

      # Email sending.
      #
      # Receiving email is not currently supported.
      sendemail = {
        enable = true;
        html = false;
        connectTimeout = "10sec";
        from = "Code Review <noreply@ponderoos.com>";
        includeDiff = true;
        smtpEncryption = "none";
        smtpServer = "localhost";
        smtpServerPort = 25;
      };
    };

    #   # Replication of the depot repository to secondary machines, for
    #   # serving cgit/josh.
    #   replicationSettings = {
    #     gerrit.replicateOnStartup = true;

    #     remote.sanduny = {
    #       url = "depot@sanduny.tvl.su:/var/lib/depot";
    #       projects = "depot";
    #     };

    #     remote.bugry = {
    #       url = "depot@bugry.ponderoos.com:/var/lib/depot";
    #       projects = "depot";
    #     };
    #   };
  };

  systemd.services.gerrit = {
    serviceConfig = {
      # There seems to be no easy way to get `DynamicUser` to play
      # well with other services (e.g. by using SupplementaryGroups,
      # which seem to have no effect) so we force the DynamicUser
      # setting for the Gerrit service to be disabled and reuse the
      # existing 'git' user.
      DynamicUser = lib.mkForce false;
      User = "git";
      Group = "git";
    };
  };

  users = {
    # Set up a user & group for git shenanigans
    groups.git = { };
    users.git = {
      group = "git";
      isSystemUser = true;
      createHome = true;
      home = "/var/lib/git";
    };
  };

  services.nginx.virtualHosts."cl-shortlink" = {
    serverName = "cl";
    extraConfig = "return 302 https://cl.ponderoos.com$request_uri;";
  };

  services.nginx.virtualHosts.gerrit = {
    serverName = "cl.ponderoos.com";
    enableACME = true;
    forceSSL = true;

    extraConfig = ''
      location / {
        proxy_pass http://localhost:4778;
        proxy_set_header  X-Forwarded-For $remote_addr;
        # The :443 suffix is a workaround for https://b.tvl.fyi/issues/88.
        proxy_set_header  Host $host:443;
      }

      location = /robots.txt {
        return 200 'User-agent: *\nDisallow: /';
      }

      add_header X-Robots-Tag "none";
    '';
  };

  services.depot.restic = {
    paths = [ "/var/lib/gerrit" "/var/cache/gerrit" ];
    exclude = [ "/var/lib/gerrit/tmp" ];
  };
}
