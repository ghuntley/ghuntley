# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{
  # TODO(proxy): ensure 256gb of space is available or adjust
  # TODO(proxy): configure networking ranges
  # TODO(proxy): configure reverse proxy
  # TODO(proxy): mitm & log network requests
  # TODO(proxy): configure memory size

  services.squid = {
    enable = false;
    configText =
      ''
        acl localnet src 10.10.10.0/24  # lan
        acl SSL_ports port 443          # https
        acl Safe_ports port 80          # http
        acl Safe_ports port 21          # ftp
        acl Safe_ports port 443         # https
        #acl Safe_ports port 1025-65535  # unregistered ports
        acl CONNECT method CONNECT

        # Deny requests to certain unsafe ports
        http_access deny !Safe_ports

        # Deny CONNECT to other than secure SSL ports
        http_access deny CONNECT !SSL_ports

        # https://wiki.squid-cache.org/Features/CacheManager
        http_access allow localnet manager
        http_access allow localhost manager
        http_access deny manager

        # Protect innocent web applications running on the proxy server who think the only
        # one who can access services on "localhost" is a local user
        http_access deny to_localhost

        # Application logs to syslog, access and store logs have specific files
        cache_log       syslog
        access_log      stdio:/var/log/squid/access.log
        cache_store_log stdio:/var/log/squid/store.log

        # Required by systemd service
        pid_filename    /run/squid.pid

        # Run as user and group squid
        cache_effective_user squid squid

        # Example rule allowing access from your local networks.
        # Adapt localnet in the ACL section to list your (internal) IP networks
        # from where browsing should be allowed
        http_access allow localnet
        http_access allow localhost

        # And finally deny all other access to this proxy
        http_access deny all

        # Squid normally listens to port 3128
        http_port 3128

        # Leave coredumps in the first cache dir
        coredump_dir /var/cache/squid

        ftp_user anonymous@example.com
        always_direct allow all

        cache_mem 3072 MB
        maximum_object_size 10240 MB
        maximum_object_size_in_memory 8 MB

        cache_dir aufs /var/cache/squid 128000 16 256
        cache_replacement_policy heap LFUDA

        # https://www.midnightfreddie.com/using-squid-to-cache-apt-updates-for-debian-and-ubuntu.html 
        refresh_pattern Packages\.bz2$ 0       20%     4320 refresh-ims
        refresh_pattern Sources\.bz2$  0       20%     4320 refresh-ims
        refresh_pattern Release\.gpg$  0       20%     4320 refresh-ims
        refresh_pattern Release$       0       20%     4320 refresh-ims
        refresh_pattern -i .deb$ 129600 100% 129600 refresh-ims override-expire

        # https://wiki.squid-cache.org/SquidFaq/WindowsUpdate
        refresh_pattern -i microsoft.com/.*\.(cab|exe|ms[i|u|f]|[ap]sf|wm[v|a]|dat|zip) 4320 80% 43200 reload-into-ims
        refresh_pattern -i windowsupdate.com/.*\.(cab|exe|ms[i|u|f]|[ap]sf|wm[v|a]|dat|zip) 4320 80% 43200 reload-into-ims
        refresh_pattern -i windows.com/.*\.(cab|exe|ms[i|u|f]|[ap]sf|wm[v|a]|dat|zip) 4320 80% 43200 reload-into-ims

        # https://gist.github.com/hvrauhal/f98d7811f19ad1792210
        refresh_pattern registry.npmjs.org 900 20% 4320 ignore-auth ignore-private ignore-no-cache ignore-reload override-expire

        # nuget
        refresh_pattern api.nuget.org 900 20% 4320 ignore-auth ignore-private ignore-no-cache ignore-reload override-expire

        # haskell
        refresh_pattern hackage.haskell.org 900 20% 4320 ignore-auth ignore-private ignore-no-cache ignore-reload override-expire

        # https://nixos.wiki/wiki/FAQ/Private_Cache_Proxy
        refresh_pattern -i nix-cache-info$ 0       20%     4320 refresh-ims
        refresh_pattern -i cache.nixos.org/nar.* 129600 100% 129600 refresh-ims override-expire

        #
        # Add any of your own refresh_pattern entries above these.
        #
        refresh_pattern ^ftp:           1440    20%     10080
        refresh_pattern ^gopher:        1440    0%      1440
        refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
        refresh_pattern .               0       20%     4320
      '';

  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 8081 3128 ];
  };

}
