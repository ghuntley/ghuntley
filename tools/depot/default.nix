# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

# depot helps you build planets
#
# it is a tool for working with monorepos in the style of tvl's depot
{ pkgs, ... }:

pkgs.stdenv.mkDerivation {
  name = "depot";
  src = ./.;
  dontInstall = true;

  nativeBuildInputs = [ pkgs.chicken ];
  buildInputs = with pkgs.chickenPackages.chickenEggs; [
    matchable
    srfi-13
  ];

  propagatedBuildInputs = [ pkgs.git ];

  buildPhase = ''
    mkdir -p $out/bin
    csc -o $out/bin/depot -static ${./depot.scm}
  '';
}
