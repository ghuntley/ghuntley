# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, lib, ... }:

# TODO: use upstream otel-cli at https://github.com/NixOS/nixpkgs/pull/143475 when it merges
pkgs.buildGoModule rec {
  pname = "otel-cli";
  version = "0.0.20";
  vendorSha256 = "sha256-S2uy57R9W5CJtL8M6kYyaOaRXlUGtCPojvyjG8XT/G0=";

  src = depot.third_party.sources.otel-cli;

  # doCheck set to false due to "main_test.go:38: otel-cli must be built and present as ./otel-cli for this test suite to work (try: go build)"
  doCheck = false;

  meta = with lib; {
    description = "a command-line tool for sending OpenTelemetry traces";
    homepage = https://github.com/equinix-labs/otel-cli;
    license = licenses.asl20;
  };
}
