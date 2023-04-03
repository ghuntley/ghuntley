# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

# Shell derivation to invoke //nix/lazy-deps with the dependencies
# that should be lazily made available in depot.
{ pkgs, depot, ... }:

depot.nix.lazy-deps {

  # shell aliases
  deploy-dns.attr = "tools.shell-alias-deploy-dns";
  deploy-nixos.attr = "tools.shell-alias-deploy-nixos";
  lg.attr = "tools.shell-alias-lg";
  z.attr = "tools.shell-alias-z";

  # depot
  age-keygen.attr = "third_party.nixpkgs.age";
  age.attr = "third_party.nixpkgs.age";
  cachix.attr = "third_party.nixpkgs.cachix";

  depot.attr = "tools.depot";
  depot-addlicense.attr = "tools.depot-addlicense";
  depot-fmt.attr = "tools.depot-fmt";
  depot-precommit.attr = "tools.depot-precommit";
  depot-src.attr = "tools.depot-src";
  depot-src-add.attr = "tools.depot-src-add";
  depot-src-update.attr = "tools.depot-src-update";
  depot-src-drop.attr = "tools.depot-src-drop";

  direnv.attr = "third_party.nixpkgs.direnv";
  gitleaks.attr = "third_party.nixpkgs.gitleaks";
  gptcommit.attr = "third_party.nixpkgs.gptcommit";
  niv.attr = "third_party.nixpkgs.niv";
  pre-commit.attr = "third_party.nixpkgs.pre-commit";

  # devshell
  ag.attr = "third_party.nixpkgs.silver-searcher";
  ack.attr = "third_party.nixpkgs.ack";
  agenix.attr = "third_party.agenix.cli";
  bat.attr = "third_party.nixpkgs.bat";
  curl.attr = "third_party.nixpkgs.curl";
  elinks.attr = "third_party.nixpkgs.elinks";
  file.attr = "third_party.nixpkgs.file";
  hash-password.attr = "tools.hash-password";
  lazygit.attr = "third_party.nixpkgs.lazygit";
  moreutils.attr = "third_party.nixpkgs.moreutils";
  tmate.attr = "third_party.nixpkgs.tmate";
  tmux.attr = "third_party.nixpkgs.tmux";
  wget.attr = "third_party.nixpkgs.wget";
  unzip.attr = "third_party.nixpkgs.unzip";

  # programming
  ghc.attr = "third_party.nixpkgs.haskell.compiler.ghc923";
  go.attr = "third_party.nixpkgs.go_1_20";
  node.attr = "third_party.nixpkgs.nodejs-18_x";
  python.attr = "third_party.nixpkgs.python38";
  rustc.attr = "third_party.nixpkgs.rustc";
  cargo.attr = "third_party.nixpkgs.cargo";

  # ops
  gcloud.attr = "third_party.nixpkgs.google-cloud-sdk";
  terraform.attr = "third_party.nixpkgs.terraform";
  nixos-shell.attr = "third_party.nixpkgs.nixos-shell";

  # experimental
  microvm.attr = "third_party.microvm";
}
