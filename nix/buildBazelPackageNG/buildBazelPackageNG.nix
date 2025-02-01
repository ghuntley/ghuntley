# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT


{ stdenv
, lib
, pkgs
, coreutils
}:

{ name ? "${baseAttrs.pname}-${baseAttrs.version}"
, bazelTargets
, bazel ? pkgs.bazel
, depsHash
, extraCacheInstall ? ""
, extraBuildSetup ? ""
, extraBuildInstall ? ""
, ...
}@baseAttrs:

let
  cleanAttrs = lib.flip removeAttrs [
    "bazelTargets"
    "depsHash"
    "extraCacheInstall"
    "extraBuildSetup"
    "extraBuildInstall"
  ];
  attrs = cleanAttrs baseAttrs;

  base = stdenv.mkDerivation (attrs // {
    nativeBuildInputs = (attrs.nativeBuildInputs or [ ]) ++ [
      bazel
    ];

    preUnpack = ''
      if [[ ! -d $HOME ]]; then
        export HOME=$NIX_BUILD_TOP/home
        mkdir -p $HOME
      fi
    '';

    bazelTargetNames = builtins.attrNames bazelTargets;
  });

  cache = base.overrideAttrs (base: {
    name = "${name}-deps";

    bazelPhase = "cache";

    buildPhase = ''
      runHook preBuild

      bazel sync --repository_cache=repository-cache $bazelFlags "''${bazelFlagsArray[@]}"
      bazel build --repository_cache=repository-cache --nobuild $bazelFlags "''${bazelFlagsArray[@]}" $bazelTargetNames

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir $out
      echo "${bazel.version}" > $out/bazel_version
      cp -R repository-cache $out/repository-cache
      ${extraCacheInstall}

      runHook postInstall
    '';

    outputHashMode = "recursive";
    outputHash = depsHash;
  });

  build = base.overrideAttrs (base: {
    bazelPhase = "build";

    inherit cache;

    nativeBuildInputs = (base.nativeBuildInputs or [ ]) ++ [
      coreutils
    ];

    buildPhase = ''
      runHook preBuild

      ${extraBuildSetup}
      bazel build --repository_cache=$cache/repository-cache $bazelFlags "''${bazelFlagsArray[@]}" $bazelTargetNames

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      ${builtins.concatStringsSep "\n" (lib.mapAttrsToList (target: outPath: lib.optionalString (outPath != null) ''
        TARGET_OUTPUTS="$(bazel cquery --repository_cache=$cache/repository-cache $bazelFlags "''${bazelFlagsArray[@]}" --output=files "${target}")"
        if [[ "$(echo "$TARGET_OUTPUTS" | wc -l)" -gt 1 ]]; then
          echo "Installing ${target}'s outputs ($TARGET_OUTPUTS) into ${outPath} as a directory"
          mkdir -p "${outPath}"
          cp $TARGET_OUTPUTS "${outPath}"
        else
          echo "Installing ${target}'s output ($TARGET_OUTPUTS) to ${outPath}"
          mkdir -p "${dirOf outPath}"
          cp "$TARGET_OUTPUTS" "${outPath}"
        fi
      '') bazelTargets)}
      ${extraBuildInstall}

      runHook postInstall
    '';
  });
in
build
