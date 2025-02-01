# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

{ depot, pkgs, lib, ... }:

let
  classPath = lib.concatStringsSep ":" [
    "${depot.third_party.gerrit}/share/api/extension-api_deploy.jar"
  ];
in
pkgs.stdenvNoCC.mkDerivation rec {
  name = "${pname}-${version}.jar";
  pname = "gerrit-ponderoos";
  version = "0.0.1";

  src = ./.;

  nativeBuildInputs = with pkgs; [
    jdk
  ];

  buildPhase = ''
    mkdir $NIX_BUILD_TOP/build

    # Build Java components.
    export JAVAC="javac -cp ${classPath} -d $NIX_BUILD_TOP/build --release 11"
    $JAVAC ./HttpModule.java

    # Install static files.
    cp -R static $NIX_BUILD_TOP/build/static
  '';

  installPhase = ''
    jar --create --file $out --manifest $src/MANIFEST.MF -C $NIX_BUILD_TOP/build .
  '';
}
