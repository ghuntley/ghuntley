# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

{ pkgs, ... }:

let
  goatcounterSrc = pkgs.fetchgit {
    url = "https://github.com/arp242/goatcounter";
    rev = "c059188a3c6064b2f32f0e80bf029b1eb1b1fdbf"; # master as of the latest commit
    hash = "sha256-9oMdaJj2AziNH8aO4Wfdph+D3Ho/0u5uHC59vIJnMKM=";
  };
in
pkgs.goatcounter.overrideAttrs (old: {
  src = goatcounterSrc;

  patches = (old.patches or [ ]) ++ [
    # ./0001-feat-third_party-git-date-add-dottime-format.patch
  ];

  # Ensure vendored dependencies are used
  modVendorHash = null;
  vendorHash = null;

  # Override the build flags to use vendored dependencies
  buildFlags = old.buildFlags or [ ] ++ [
    "-mod=vendor"
  ];

  # Update vendor directory before build
  preBuildPhases = [ "updateVendorPhase" "customisePhase" ] ++ (old.preBuildPhases or [ ]);
  updateVendorPhase = ''
    export GOPROXY=https://proxy.golang.org
    go mod tidy
    go mod vendor
    export GOPROXY=off
  '';
  customisePhase = ''
    ${pkgs.rpl}/bin/rpl -R 'data-goatcounter' 'data-stats' .
    ${pkgs.rpl}/bin/rpl -R 'goatcounter' 'stats' "public/count.js"
    ${pkgs.rpl}/bin/rpl -R 'GoatCounter' 'Stats' "public/count.js"
    ${pkgs.gnused}/bin/sed -i '1d' "public/count.js"
    ${pkgs.rpl}/bin/rpl -R 'count.js' 'hello.js' .
    ${pkgs.coreutils}/bin/mv "public/count.js" "public/hello.js"
  '';
})
