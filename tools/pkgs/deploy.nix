# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ lib, rustPlatform, pkg-config, openssl }:

rustPlatform.buildRustPackage {
  pname = "deploy";
  version = "0.1.0";

  src = ../deploy;

  cargoLock = {
    lockFile = ../deploy/Cargo.lock;
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  meta = with lib; {
    description = "Deploy tool for managing depot sync and deployments";
    homepage = "https://github.com/ghuntley/ghuntley";
    license = licenses.unfree;
    maintainers = [ ];
  };
}
