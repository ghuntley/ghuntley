# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary
{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  # Import our tools overlay to get access to custom packages
  tools = pkgs.extend (import ./tools/pkgs);
  depot = tools.depot // {third_party = tools.third_party;};
in {
  # https://devenv.sh/basics/
  env.GREET = "devenv";

  # https://devenv.sh/packages/
  packages = [
    # 1st-party
    depot.tools.license
    depot.tools.deploy

    # 3rd-party tools
    depot.third_party.tools.claude
    depot.third_party.tools.amp

    # formatters
    depot.third_party.tools.treefmt

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
  languages.rust.components = ["rustc" "cargo" "clippy"];
  languages.typescript.enable = true;
  languages.javascript.pnpm.enable = true;

  # https://devenv.sh/processes/
  processes.cargo-watch.exec = "cargo-watch";

  # https://devenv.sh/scripts/
  scripts.depot.exec = ''
    # Preserve caller CWD, build and run the depot binary from tools/depot
    RUST_LOG="''${RUST_LOG:-info}" \
    cargo run --manifest-path "$DEVENV_ROOT/tools/depot/Cargo.toml" -- "$@"
  '';

  # https://devenv.sh/tasks/
  tasks = {
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
