# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, pkgs, ... }:

{
  config = {
    security.acme = {
      acceptTerms = true;
      defaults.email = "ghuntley@ghuntley.com";
    };

    services.nginx = {
      enable = true;
      enableReload = true;

      recommendedTlsSettings = true;
      recommendedGzipSettings = true;
      recommendedProxySettings = true;

      commonHttpConfig = ''
        log_format json_combined escape=json
        '{'
            '"remote_addr":"$remote_addr",'
            '"method":"$request_method",'
            '"host":"$host",'
            '"uri":"$request_uri",'
            '"status":$status,'
            '"request_size":$request_length,'
            '"response_size":$body_bytes_sent,'
            '"response_time":$request_time,'
            '"referrer":"$http_referer",'
            '"user_agent":"$http_user_agent"'
        '}';

        access_log syslog:server=unix:/dev/log,nohostname json_combined;
      '';

      appendHttpConfig = ''
        add_header Permissions-Policy "interest-cohort=()";
      '';
    };
  };
}
