# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ lib
, rustPlatform
}:

rustPlatform.buildRustPackage {
  pname = "depot";
  version = "0.1.0";

  src = ../depot;

  cargoHash = "sha256-z7MmKDX7Jgw/eKAnh6j8/bQOz4wJCxHWpcrkqnmFHHU=";

  meta = with lib; {
    description = "A build system for nix flake expressions";
    homepage = "https://github.com/ghuntley/ghuntley";
    license = licenses.unfree;
    maintainers = [ "ghuntley@ghuntley.com" ];
  };
}
