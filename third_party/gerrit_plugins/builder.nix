# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT


{ depot, lib, pkgs, ... }:
{
  buildGerritBazelPlugin =
    { name
    , version
    , src
    , depsHash ? null
    , overlayPluginCmd ? ''
        cp -R "${src}" "$out/plugins/${name}"
        echo "STABLE_BUILD_${lib.toUpper name}_LABEL v${version}-nix${if patches != [] then "-dirty" else ""}" >> $out/.version
      ''
    , postOverlayPlugin ? ""
    , postPatch ? ""
    , patches ? [ ]
    }: ((depot.third_party.gerrit.override (old: {
      name = "${name}.jar";

      src = pkgs.runCommandLocal "${name}-src" { } ''
        cp -R "${depot.third_party.gerrit.src}" "$out"
        chmod -R +w "$out"
        ${overlayPluginCmd}
        ${postOverlayPlugin}
      '';
      depsHash = (if depsHash != null then depsHash else old.depsHash);

      bazelTargets = {
        "//plugins/${name}" = "$out";
      };

      extraBuildInstall = "";
    })).overrideAttrs (super: {
      postPatch = ''
        ${super.postPatch or ""}
        pushd "plugins/${name}"
        ${lib.concatMapStringsSep "\n" (patch: ''
          patch -p1 < ${patch}
        '') patches}
        popd
        ${postPatch}
      '';
    }));
}
