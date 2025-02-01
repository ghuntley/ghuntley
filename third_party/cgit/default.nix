# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs, ... }:

let
  inherit (pkgs) stdenv gzip bzip2 xz lzip zstd zlib openssl;
in
stdenv.mkDerivation rec {
  pname = "cgit-pink";
  version = "master";
  src = ./.;

  buildInputs = [ openssl zlib ];

  enableParallelBuilding = true;

  postPatch = ''
    sed -e 's|"gzip"|"${gzip}/bin/gzip"|' \
        -e 's|"bzip2"|"${bzip2.bin}/bin/bzip2"|' \
        -e 's|"lzip"|"${lzip}/bin/lzip"|' \
        -e 's|"xz"|"${xz.bin}/bin/xz"|' \
        -e 's|"zstd"|"${zstd}/bin/zstd"|' \
        -i ui-snapshot.c
  '';

  # Give cgit the git source tree including depot patches. Note that
  # the version expected by cgit should be kept in sync with the
  # version available in nixpkgs.
  #
  # TODO(tazjin): Add an assert for this somewhere so we notice it on
  # channel bumps.
  preBuild =
    let
      # we have to give cgit a git with dottime support to build
      git' = pkgs.git.overrideAttrs (old: {
        src = pkgs.fetchurl {
          url = "https://github.com/git/git/archive/refs/tags/v2.44.2.tar.gz";
          hash = "sha256-3h0LBfAD4MXfZc0tjWQDO81UdbRo3w5C0W7j7rr9m9I=";
        };
        patches = (old.patches or [ ]) ++ [
          ../git/0001-feat-third_party-git-date-add-dottime-format.patch
        ];
      });
    in
    ''
      rm -rf git # remove submodule dir ...
      cp -r --no-preserve=ownership,mode ${pkgs.srcOnly git'} git
      makeFlagsArray+=(prefix="$out" CGIT_SCRIPT_PATH="$out/cgit/")
      cat tvl-extra.css >> cgit.css
    '';

  stripDebugList = [ "cgit" ];

  # We don't use the filters and they require wrapping to find their deps
  postInstall = ''
    rm -rf "$out/lib/cgit/filters"
    find "$out" -type d -empty -delete
  '';

  meta = {
    hompepage = "https://git.causal.agency/cgit-pink/";
    description = "cgit fork aiming for better maintenance";
    license = lib.licenses.gpl2;
    platforms = lib.platforms.linux;
  };
}
