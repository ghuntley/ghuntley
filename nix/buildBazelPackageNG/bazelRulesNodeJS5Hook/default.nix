# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

{ stdenvNoCC
, lib
, makeSetupHook
, fetchFromGitHub
, coreutils
, gnugrep
, nodejs
, yarn
, git
, cacert
}:
let
  rulesNodeJS = stdenvNoCC.mkDerivation rec {
    pname = "bazelbuild-rules_nodejs";
    version = "5.8.5";

    src = fetchFromGitHub {
      owner = "bazelbuild";
      repo = "rules_nodejs";
      rev = version;
      hash = "sha256-6UbYRrOnS93+pK4VI016gQZv2jLCzkJn6wJ4vZNCNjY=";
    };

    dontBuild = true;

    postPatch = ''
      shopt -s globstar
      for i in **/*.bzl **/*.sh **/*.cjs; do
        substituteInPlace "$i" \
          --replace-quiet '#!/usr/bin/env bash' '#!${stdenvNoCC.shell}' \
          --replace-quiet '#!/bin/bash' '#!${stdenvNoCC.shell}'
      done
      sed -i '/^#!/a export PATH=${lib.makeBinPath [ coreutils gnugrep ]}:$PATH' internal/node/launcher.sh
    '';

    installPhase = ''
      cp -R . $out
    '';
  };
in
makeSetupHook
{
  name = "bazelbuild-rules_nodejs-5-hook";
  propagatedBuildInputs = [
    nodejs
    yarn
    git
    cacert
  ];
  substitutions = {
    inherit nodejs yarn cacert rulesNodeJS;
    local_node = ./local_node;
    local_yarn = ./local_yarn;
  };
} ./setup-hook.sh
