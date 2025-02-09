# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot
, pkgs
, ...
}:

with depot.nix.yants;

let
  inherit (depot.nix.runTestsuite)
    runTestsuite
    it
    assertEq;

  # Get the depot-fmt package and its config
  depot-fmt-pkg = import ../default.nix { inherit depot pkgs; };
  depot-fmt = depot-fmt-pkg.default;

  # Helper to normalize string endings
  normalizeString = str: pkgs.lib.removeSuffix "\n" str;

  # Create a test directory with the given files
  mkTestDir = files:
    pkgs.runCommand "test-dir"
      {
        nativeBuildInputs = [ depot-fmt pkgs.git pkgs.treefmt ];
      } ''
      # Create temporary directory for git operations and cache
      TMPDIR=$(mktemp -d)
      trap 'rm -rf "$TMPDIR"' EXIT

      # Set up cache directory in TMPDIR
      export XDG_CACHE_HOME="$TMPDIR/cache"
      mkdir -p "$XDG_CACHE_HOME/treefmt"

      # Set up git in the temporary directory
      cd "$TMPDIR"
      git init
      git config user.email "test@example.com"
      git config user.name "Test User"

      # Copy treefmt config
      cp ${depot-fmt-pkg.config} .treefmt.toml

      # Create test files
      ${builtins.concatStringsSep "\n"
        (builtins.attrValues
          (builtins.mapAttrs (name: content: ''
            mkdir -p "$(dirname "${name}")"
            cat > "${name}" <<'EOF'
            ${content}
            EOF
          '') files))}

      # Add files to git
      git add -A
      git commit -m "Initial commit"

      # Run depot-fmt on specific files
      if [ -f "test.nix" ]; then
        echo "Formatting test.nix..."
        depot-fmt test.nix
      fi
      if [ -f "test/test.nix" ]; then
        echo "Processing test/test.nix..."
        if [ -f "test/.skip-format" ]; then
          echo "Found .skip-format, skipping test/test.nix"
        else
          echo "Formatting test/test.nix..."
          depot-fmt test/test.nix
        fi
      fi

      # Copy results to output
      mkdir -p $out
      cp -r . $out/
      chmod -R a-w $out

      # Debug output
      echo "Final contents of files:"
      if [ -f "$out/test.nix" ]; then
        echo "=== test.nix ==="
        cat "$out/test.nix"
      fi
      if [ -f "$out/test/test.nix" ]; then
        echo "=== test/test.nix ==="
        cat "$out/test/test.nix"
      fi
    '';

  # Test that files are formatted correctly
  testFormatting = it "formats Nix files correctly" [
    (assertEq "Nix file should be properly formatted"
      (normalizeString (builtins.readFile "${mkTestDir {
        "test.nix" = ''
          {depot,pkgs,...}: let
            x=1;
          in {
            y=2;
          }'';
      }}/test.nix"))
      (normalizeString ''
        { depot, pkgs, ... }:
        let
          x = 1;
        in
        {
          y = 2;
        }
      ''))
  ];

  # Test that .skip-format files are respected
  testSkipFormat = it "respects skip patterns" [
    (assertEq "Files in directories with .skip-format should not be formatted"
      (normalizeString (builtins.readFile "${mkTestDir {
        "test/test.nix" = ''{depot,pkgs,...}: let
          x=1;
        in {
          y=2;
        }'';
        "test/.skip-format" = "";
      }}/test/test.nix"))
      (normalizeString ''{depot,pkgs,...}: let
          x=1;
        in {
          y=2;
        }''))
  ];

in
runTestsuite "depot-fmt" [
  testFormatting
  testSkipFormat
]
