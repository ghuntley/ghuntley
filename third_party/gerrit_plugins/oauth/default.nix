# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

{ depot, pkgs, ... }@args:

let
  inherit (import ../builder.nix args) buildGerritBazelPlugin;
in
buildGerritBazelPlugin rec {
  name = "oauth";
  version = "98231604d60788bb43490f1a301d792817ac8008";
  src = pkgs.fetchgit {
    url = "https://gerrit.googlesource.com/plugins/oauth";
    rev = "81a20219fa4bbf60f8996cb46d46ebc5ea0c11ee";
    hash = "sha256-AuVO1Yys8BYqGHZI/adszCUg0JM2v4Td4fe26LdOPLM=";
  };
  depsHash = "sha256-Xx607OSqlRMr8mlkVhfXiqM9hWcJqx4dmpf+cm10uSA=";
  postOverlayPlugin = ''
    cp "${src}/external_plugin_deps.bzl" "$out/plugins/external_plugin_deps.bzl"
  '';
}
