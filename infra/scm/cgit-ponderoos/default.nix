# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT


# Wrapper for running cgit through thttpd with TVL-specific
# configuration.
#
# In practice this is only used for //ops/modules/cgit, but exposing
# it here makes it easy to experiment with cgit locally.
{ depot, lib, pkgs, ... }:

# TODO - add cheddar
# about-filter=${depot.tools.cheddar.about-filter}/bin/cheddar-about
# source-filter=${depot.tools.cheddar}/bin/cheddar

let
  cgitConfig = repo: pkgs.writeText "cgitrc" ''
    # Global configuration
    virtual-root=/
    enable-http-clone=0
    readme=:README.md
    enable-log-filecount=1
    enable-log-linecount=1
    enable-follow-links=0
    enable-blame=1
    mimetype-file=${pkgs.mime-types}/etc/mime.types
    logo=https://static.ponderoos.com/${depot.web.static.drvHash}/logo-animated.svg

    # Repository configuration
    repo.url=depot
    repo.path=${repo}
    repo.desc=monorepo for Ponderoos
    repo.owner=Ponderoos
    repo.clone-url=https://code.ponderoos.com/depot.git
  '';

  thttpdConfig = port: pkgs.writeText "thttpd.conf" ''
    port=${toString port}
    dir=${depot.third_party.cgit}/cgit
    nochroot
    novhost
    cgipat=**.cgi
  '';

  # Patched version of thttpd that serves cgit.cgi as the index and
  # sets the environment variable for pointing cgit at the correct
  # configuration.
  #
  # Things are done this way because recompilation of thttpd is much
  # faster than cgit.
  thttpdConfigPatch = repo: pkgs.writeText "thttpd_cgit_conf.patch" ''
    diff --git a/libhttpd.c b/libhttpd.c
    index c6b1622..eef4b73 100644
    --- a/libhttpd.c
    +++ b/libhttpd.c
    @@ -3055,4 +3055,6 @@ make_envp( httpd_conn* hc )

         envn = 0;
    +    // force cgit to load the correct configuration
    +    envp[envn++] = "CGIT_CONFIG=${cgitConfig repo}";
         envp[envn++] = build_env( "PATH=%s", CGI_PATH );
     #ifdef CGI_LD_LIBRARY_PATH
  '';

  thttpdCgit = repo: pkgs.thttpd.overrideAttrs (old: {
    patches = [
      ./thttpd_cgi_idx.patch
      (thttpdConfigPatch repo)
    ];
  });

in
lib.makeOverridable
  ({ port ? 2448
   , repo ? "/var/lib/gerrit/git/depot.git/"
   }: pkgs.writeShellScript "cgit-launch" ''
    exec ${thttpdCgit repo}/bin/thttpd -D -C ${thttpdConfig port}
  '')
{ }
