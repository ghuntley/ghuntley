# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Expose all static assets as a folder. The derivation contains a
# `drvHash` attribute which can be used for cache-busting.
{ depot, lib, pkgs, ... }:

let
  storeDirLength = with builtins; (stringLength storeDir) + 1;
  logo = depot.web.tvl.logo;
in
lib.fix (self: pkgs.runCommand "tvl-static"
{
  passthru = {
    # Preserving the string context here makes little sense: While we are
    # referencing this derivation, we are not doing so via the nix store,
    # so it makes little sense for Nix to police the references.
    drvHash = builtins.unsafeDiscardStringContext (
      lib.substring storeDirLength 32 self.drvPath
    );
  };
} ''
  mkdir $out
  cp -r ${./.}/* $out
  cp ${logo.pastelRainbow} $out/logo-animated.svg
  cp ${logo.bluePng} $out/logo-blue.png
  cp ${logo.greenPng} $out/logo-green.png
  cp ${logo.orangePng} $out/logo-orange.png
  cp ${logo.purplePng} $out/logo-purple.png
  cp ${logo.redPng} $out/logo-red.png
  cp ${logo.yellowPng} $out/logo-yellow.png
'')
