# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary
{
  lib,
  rustPlatform,
  git,
  makeWrapper,
}:
rustPlatform.buildRustPackage {
  pname = "depot";
  version = "0.2.0";

  src = ../depot;

  cargoHash = "sha256-cR3+DP49mPmaEltfAqBvZI14ASI8I59huJCmVXGMASM=";

  nativeBuildInputs = [makeWrapper];

  postInstall = ''
    wrapProgram $out/bin/depot \
      --prefix PATH : ${lib.makeBinPath [git]}
  '';

  meta = with lib; {
    description = "A build system for nix flake expressions";
    homepage = "https://github.com/ghuntley/ghuntley";
    license = licenses.unfree;
    maintainers = ["ghuntley@ghuntley.com"];
  };
}
