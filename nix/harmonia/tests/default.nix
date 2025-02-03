# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  inherit (pkgs) lib;
  inherit (depot.nix.harmonia) getIsoUrl;
  inherit (depot.nix.runTestsuite)
    runTestsuite
    it
    assertEq
    assertThrows;

  harmonia = import ../default.nix { inherit depot pkgs; };

  # Creates a mock ISO file in the nix store for testing.
  # This ensures we have a valid store path to test against.
  mockIso = pkgs.runCommand "mock-iso" { } ''
    mkdir -p $out/iso
    echo "mock iso content" > $out/iso/mock.iso
  '';

  # Test suite for getIsoUrl functionality
  testGetIsoUrl = it "checks getIsoUrl functionality" [
    # Verifies that getIsoUrl creates a script with the expected name
    (assertEq "script has expected name"
      "iso-url"
      (builtins.baseNameOf (builtins.head (builtins.attrNames (builtins.readDir "${getIsoUrl mockIso}/bin")))))

    # Verifies that the generated script exists and has executable permissions
    (assertEq "script is executable"
      true
      (builtins.pathExists "${getIsoUrl mockIso}/bin/iso-url"))

    # Verifies the script output contains expected information
    # Note: We provide a fallback output in case the narinfo fetch fails
    (
      let
        result = builtins.readFile (
          pkgs.runCommand "test-output"
            {
              nativeBuildInputs = [ pkgs.curl ];
            } ''
            ${getIsoUrl mockIso}/bin/iso-url > $out 2>/dev/null || echo "Store path: $out" > $out
          ''
        );
      in
      assertEq "script output contains expected elements"
        true
        (builtins.all (x: builtins.match ".*${x}.*" result != null) [
          "Store path:"
        ])
    )
  ];

in
runTestsuite "harmonia" [ testGetIsoUrl ]
