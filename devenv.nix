# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, lib, config, inputs, ... }:

let
  # Import our tools overlay to get access to custom packages
  tools = pkgs.extend (import ./tools/pkgs);
in
{

  # https://devenv.sh/basics/
  env.GREET = "devenv";
  
  # https://devenv.sh/packages/
  packages = [ 
    # 1st-party
    tools.license

    # 3rd-party
    pkgs.age
    pkgs.btop
    pkgs.cargo-watch
    pkgs.cosign
    pkgs.curl
    pkgs.docker
    pkgs.dive
    pkgs.dprint
    pkgs.git
    pkgs.jq
    pkgs.k9s
    pkgs.kubectl
    pkgs.mold
    pkgs.opentofu
    pkgs.lld
    pkgs.nixos-rebuild
    pkgs.nodejs_20
    pkgs.pnpm_9
    pkgs.skopeo
    pkgs.sops
    pkgs.ssh-to-age
    (pkgs.opentofu.withPlugins (p: [
      p.cloudflare
    ]))
  ];

  # https://devenv.sh/languages/
  languages.rust.enable = true;
  languages.rust.components = [ "rustc" "cargo" "clippy" ];
  languages.typescript.enable = true;
  languages.javascript.pnpm.enable = true;

  # https://devenv.sh/processes/
  processes.cargo-watch.exec = "cargo-watch";
  
  # https://devenv.sh/tasks/
  tasks = {
    "infra:hammer:test".exec = "scripts/infra/hammer-test.sh";
    "infra:hammer:deploy".exec = "scripts/infra/hammer-deploy.sh";

    "license:check".exec = "scripts/license/check.sh";
    "license:check:all".exec = "scripts/license/check-all.sh";
    "license:add".exec = "scripts/license/add.sh";
    "license:add:all".exec = "scripts/license/add-all.sh";
  };

  # https://devenv.sh/tests/
  enterTest = ''
  '';

  # Shell aliases and helper functions
  enterShell = ''
    alias claude="$DEVENV_ROOT/node_modules/.bin/claude --dangerously-skip-permissions $@"    
  '';

  # https://devenv.sh/git-hooks/
  git-hooks.hooks = {
    shellcheck.enable = true;       
  };

  # See full reference at https://devenv.sh/reference/options/
}
